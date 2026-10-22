import CryptoKit
import Foundation

struct HTTPSStaticIndexProvider: ExtensionSourceProvider {
    static let maximumCatalogBytes = 4 * 1_024 * 1_024
    static let maximumPackageBytes: Int64 = 512 * 1_024 * 1_024

    let identifier: ExtensionSourceProviderID = .httpsStaticIndex
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(_ source: ExtensionSource) async throws {
        guard source.providerID == identifier,
              let components = URLComponents(url: source.location, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ExtensionSourceProviderError.invalidConfiguration("A credential-free HTTPS catalog URL is required.")
        }
    }

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh {
        try await validate(source)
        var request = URLRequest(url: source.location)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let entityTag = cached?.entityTag {
            request.setValue(entityTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cached?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  isSameOrigin(response.url, source.location) else {
                throw ExtensionSourceProviderError.unsupportedRedirect
            }
            if response.statusCode == 304 {
                guard let cached else { throw ExtensionSourceProviderError.invalidResponse }
                return ExtensionCatalogRefresh(
                    catalog: cached.catalog,
                    entityTag: response.value(forHTTPHeaderField: "ETag"),
                    lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                    notModified: true
                )
            }
            guard response.statusCode == 200 else {
                throw ExtensionSourceProviderError.transport("Catalog server returned HTTP \(response.statusCode).")
            }
            guard response.expectedContentLength < 0
                    || response.expectedContentLength <= Self.maximumCatalogBytes else {
                throw ExtensionSourceProviderError.responseTooLarge
            }

            var data = Data()
            data.reserveCapacity(
                response.expectedContentLength > 0 ? Int(response.expectedContentLength) : 64 * 1_024
            )
            var chunk = Data()
            chunk.reserveCapacity(64 * 1_024)
            for try await byte in bytes {
                guard data.count + chunk.count < Self.maximumCatalogBytes else {
                    throw ExtensionSourceProviderError.responseTooLarge
                }
                chunk.append(byte)
                if chunk.count >= 64 * 1_024 {
                    data.append(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            data.append(chunk)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let catalog = try decoder.decode(ExtensionCatalog.self, from: data)
            try ExtensionCatalogValidator.validate(catalog)
            return ExtensionCatalogRefresh(
                catalog: catalog,
                entityTag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                notModified: false
            )
        } catch is CancellationError {
            throw ExtensionSourceProviderError.cancelled
        } catch let error as ExtensionSourceProviderError {
            throw error
        } catch is ExtensionCatalogValidationError {
            throw ExtensionSourceProviderError.invalidResponse
        } catch is DecodingError {
            throw ExtensionSourceProviderError.invalidResponse
        } catch {
            if Task.isCancelled { throw ExtensionSourceProviderError.cancelled }
            throw ExtensionSourceProviderError.transport(String(describing: error))
        }
    }

    func download(
        _ package: ExtensionCatalogVersion,
        from source: ExtensionSource,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> DownloadedExtensionPackage {
        try await validate(source)
        guard let url = resolvedURL(package.url, relativeTo: source.location),
              isSameOrigin(url, source.location) else {
            throw ExtensionSourceProviderError.invalidConfiguration(
                "Package URL must use the catalog origin over HTTPS."
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  isSameOrigin(response.url, source.location) else {
                throw ExtensionSourceProviderError.unsupportedRedirect
            }
            guard response.statusCode == 200 else {
                throw ExtensionSourceProviderError.transport("Package server returned HTTP \(response.statusCode).")
            }
            guard response.expectedContentLength < 0
                    || response.expectedContentLength <= Self.maximumPackageBytes else {
                throw ExtensionSourceProviderError.responseTooLarge
            }

            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                throw ExtensionSourceProviderError.transport("Could not create package staging file.")
            }
            do {
                let handle = try FileHandle(forWritingTo: destination)
                defer { try? handle.close() }
                var hasher = SHA256()
                var byteCount: Int64 = 0
                var buffer = Data()
                buffer.reserveCapacity(64 * 1_024)
                for try await byte in bytes {
                    guard byteCount < Self.maximumPackageBytes else {
                        throw ExtensionSourceProviderError.responseTooLarge
                    }
                    buffer.append(byte)
                    byteCount += 1
                    if buffer.count >= 64 * 1_024 {
                        try handle.write(contentsOf: buffer)
                        hasher.update(data: buffer)
                        buffer.removeAll(keepingCapacity: true)
                        progress(byteCount, response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
                    }
                }
                if !buffer.isEmpty {
                    try handle.write(contentsOf: buffer)
                    hasher.update(data: buffer)
                }
                try handle.synchronize()
                let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                guard digest == package.integrity else {
                    throw ExtensionSourceProviderError.integrityMismatch
                }
                progress(byteCount, response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
                return DownloadedExtensionPackage(fileURL: destination, byteCount: byteCount)
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw ExtensionSourceProviderError.cancelled
        } catch let error as ExtensionSourceProviderError {
            try? FileManager.default.removeItem(at: destination)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw ExtensionSourceProviderError.cancelled }
            throw ExtensionSourceProviderError.transport(String(describing: error))
        }
    }

    private func resolvedURL(_ packageURL: URL, relativeTo catalogURL: URL) -> URL? {
        guard let components = URLComponents(url: packageURL, resolvingAgainstBaseURL: false) else { return nil }
        let resolved: URL?
        if packageURL.scheme == nil {
            resolved = URL(string: packageURL.relativeString, relativeTo: catalogURL)?.absoluteURL
        } else {
            resolved = packageURL
        }
        guard let resolved,
              let resolvedComponents = URLComponents(url: resolved, resolvingAgainstBaseURL: false),
              resolvedComponents.scheme?.lowercased() == "https",
              resolvedComponents.user == nil,
              resolvedComponents.password == nil,
              resolvedComponents.query == nil,
              resolvedComponents.fragment == nil,
              components.host == nil || components.host?.lowercased() == resolvedComponents.host?.lowercased() else {
            return nil
        }
        return resolved
    }

    private func isSameOrigin(_ candidate: URL?, _ reference: URL) -> Bool {
        guard let candidate,
              let candidateComponents = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              let referenceComponents = URLComponents(
                url: reference,
                resolvingAgainstBaseURL: false
              ) else { return false }
        return candidateComponents.scheme?.lowercased() == "https"
            && candidateComponents.scheme?.lowercased() == referenceComponents.scheme?.lowercased()
            && candidateComponents.host?.lowercased() == referenceComponents.host?.lowercased()
            && (candidateComponents.port ?? 443) == (referenceComponents.port ?? 443)
    }
}
