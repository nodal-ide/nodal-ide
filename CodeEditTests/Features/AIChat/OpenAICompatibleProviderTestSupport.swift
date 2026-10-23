import Foundation

struct AssistantStubReply: @unchecked Sendable {
    var statusCode = 200
    var headers: [String: String] = [:]
    var chunks: [Data] = []
    var failure: URLError?
    var finalURL: URL?
    var delayNanoseconds: UInt64 = 0
}

class AssistantStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replyProvider: ((URLRequest) -> AssistantStubReply)?
    nonisolated(unsafe) private static var storedRequest: URLRequest?
    private static let requestLock = NSLock()

    static var lastRequest: URLRequest? {
        requestLock.lock()
        defer { requestLock.unlock() }
        return storedRequest
    }

    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let reply = Self.replyProvider?(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.requestLock.lock()
        Self.storedRequest = request
        Self.requestLock.unlock()

        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let response = HTTPURLResponse(
            url: reply.finalURL ?? url,
            statusCode: reply.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if reply.chunks.isEmpty {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            for chunk in reply.chunks {
                self.stateLock.lock()
                let isStopped = self.stopped
                self.stateLock.unlock()
                guard !isStopped else { return }
                if reply.delayNanoseconds > 0 {
                    Thread.sleep(forTimeInterval: Double(reply.delayNanoseconds) / 1_000_000_000)
                }
                self.client?.urlProtocol(self, didLoad: chunk)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }
}
