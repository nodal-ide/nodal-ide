import Darwin
import Foundation

enum LocalProxyLockError: Error, Equatable, LocalizedError {
    case alreadyLocked(URL)
    case cannotOpen(URL, code: Int32)
    case cannotLock(URL, code: Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyLocked:
            return "Another Nodal IDE instance is already managing local domains."
        case let .cannotOpen(url, code):
            return "Could not open the lock file at \(url.path(percentEncoded: false)) (errno \(code))."
        case let .cannotLock(url, code):
            return "Could not lock \(url.path(percentEncoded: false)) (errno \(code))."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .alreadyLocked:
            return "Close the other Nodal IDE window or quit the other instance, then try again."
        case .cannotOpen, .cannotLock:
            return "Check that \(LocalProxyLock.defaultDirectory.path(percentEncoded: false)) is writable."
        }
    }
}

/// Cross-process single-instance guard for the shared local proxy (`~/.codeedit/proxy`).
///
/// Binds an exclusive, non-blocking `flock` on `<proxy root>/lock`. The descriptor is opened
/// close-on-exec so nginx/PHP-FPM children never inherit the lock.
final class LocalProxyLock {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codeedit", directoryHint: .isDirectory)
            .appending(path: "proxy", directoryHint: .isDirectory)
    }

    static var defaultURL: URL {
        defaultDirectory.appending(path: "lock")
    }

    let lockFileURL: URL
    private var descriptor: Int32 = -1

    var isHeld: Bool {
        descriptor >= 0
    }

    init(lockFileURL: URL = LocalProxyLock.defaultURL) {
        self.lockFileURL = lockFileURL
    }

    deinit {
        release()
    }

    /// Takes the exclusive lock. Throws ``LocalProxyLockError/alreadyLocked(_:)`` when another
    /// holder (in this process or any other) owns the lock.
    func acquire() throws {
        guard !isHeld else {
            return
        }

        try createParentDirectoryIfNeeded()

        let path = lockFileURL.path(percentEncoded: false)
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw LocalProxyLockError.cannotOpen(lockFileURL, code: errno)
        }

        var result: Int32
        repeat {
            result = flock(descriptor, LOCK_EX | LOCK_NB)
        } while result != 0 && errno == EINTR

        guard result == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK {
                throw LocalProxyLockError.alreadyLocked(lockFileURL)
            }
            throw LocalProxyLockError.cannotLock(lockFileURL, code: code)
        }

        self.descriptor = descriptor
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }

        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    private func createParentDirectoryIfNeeded() throws {
        let directory = lockFileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false

        if FileManager.default.fileExists(
            atPath: directory.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            return
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
