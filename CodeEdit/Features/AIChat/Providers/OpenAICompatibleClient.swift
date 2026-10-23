import Foundation

struct OpenAICompatibleClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchModels(
        profile: AssistantProviderProfile,
        apiKey: String?
    ) async throws -> [String] {
        let endpoint = try AssistantEndpoint(
            baseURLString: profile.baseURL,
            allowInsecureHTTP: profile.allowInsecureHTTP
        )
        let origin = AssistantOrigin(url: endpoint.baseURL)
        var request = URLRequest(url: endpoint.modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let redirectDelegate = AssistantRedirectDelegate(origin: origin)
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AssistantProviderError.invalidResponse
            }
            guard AssistantOrigin(url: httpResponse.url)?.matches(origin) == true else {
                throw AssistantProviderError.redirectRejected
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AssistantProviderError.http(
                    statusCode: httpResponse.statusCode,
                    body: data,
                    retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After")
                )
            }
            guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
                throw AssistantProviderError.invalidResponse
            }
            return Self.orderedUniqueModels(list.data.compactMap(\.id))
        } catch {
            throw AssistantProviderError.normalize(error)
        }
    }

    static func orderedUniqueModels(_ models: [String]) -> [String] {
        var seen = Set<String>()
        let indexed = models.enumerated().compactMap { index, model -> (String, Int)? in
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return (trimmed, index)
        }
        return indexed.sorted { lhs, rhs in
            if lhs.0 == rhs.0 {
                return lhs.1 < rhs.1
            }
            return lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending
        }
        .map(\.0)
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String?
        }

        let data: [Model]
    }
}
