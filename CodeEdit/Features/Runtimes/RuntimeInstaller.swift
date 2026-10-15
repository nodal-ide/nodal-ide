//
//  RuntimeInstaller.swift
//  CodeEdit
//
//  Download + checksum helpers used by runtime providers.
//

import CryptoKit
import Foundation

enum RuntimeInstaller {
    /// The current machine architecture as used in Node.js release filenames.
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    /// Downloads `url` to `destination`, reporting progress (0…1) on the main queue.
    ///
    /// Cancelling the calling task cancels the underlying URL session task.
    static func download(_ url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let client = DownloadClient(destination: destination, progress: progress)
        try await withTaskCancellationHandler {
            try await client.start(url)
        } onCancel: {
            client.cancel()
        }
    }

    /// Returns the hex SHA-256 of a file.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1 << 20) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class DownloadClient: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: (Double) -> Void
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private let lock = NSLock()

    init(destination: URL, progress: @escaping (Double) -> Void) {
        self.destination = destination
        self.progress = progress
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func start(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            let task = session?.downloadTask(with: url)
            self.downloadTask = task
            lock.unlock()
            task?.resume()
        }
    }

    func cancel() {
        lock.lock()
        let task = downloadTask
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [progress] in progress(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}
