import Foundation

/// Static helpers shared by the certificate authority and its trust extension.
extension CertificateAuthority {
    static func replaceItem(at destination: URL, with source: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    /// A declined authorization comes back as a non-zero exit with a "canceled" message.
    static func isCancellation(_ result: ShellResult) -> Bool {
        guard !result.succeeded else {
            return false
        }
        return result.output.localizedCaseInsensitiveContains("canceled")
            || result.output.localizedCaseInsensitiveContains("cancelled")
            || result.output.contains("-128")
    }

    static func readMetadata(at url: URL) throws -> SiteCertificateMetadata {
        let data = try Data(contentsOf: url)
        return try decoder.decode(SiteCertificateMetadata.self, from: data)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func lastLine(of output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .last
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? output
    }

    /// Keeps enough of the tool output to explain failures instead of losing every line but the last.
    static func diagnosticOutput(of output: String) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return "The command did not report a reason."
        }
        return lines.suffix(4).joined(separator: " ")
    }
}
