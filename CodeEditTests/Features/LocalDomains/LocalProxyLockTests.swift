import Foundation
import Testing
@testable import CodeEdit

struct LocalProxyLockTests {
    @Test
    func acquireCreatesAndHoldsLockFile() throws {
        try withTempDir { directory in
            let lockURL = directory.appending(path: "lock")
            let lock = LocalProxyLock(lockFileURL: lockURL)

            try lock.acquire()

            #expect(lock.isHeld)
            #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))

            lock.release()
            #expect(!lock.isHeld)
        }
    }

    @Test
    func createsMissingParentDirectoryWithRestrictedPermissions() throws {
        try withTempDir { directory in
            let lockURL = directory.appending(path: "proxy", directoryHint: .isDirectory).appending(path: "lock")
            let lock = LocalProxyLock(lockFileURL: lockURL)

            try lock.acquire()

            let attributes = try FileManager.default.attributesOfItem(
                atPath: lockURL.deletingLastPathComponent().path(percentEncoded: false)
            )
            #expect(attributes[.posixPermissions] as? Int == 0o700)
        }
    }

    @Test
    func detectsSecondHolder() throws {
        try withTempDir { directory in
            let lockURL = directory.appending(path: "lock")
            let first = LocalProxyLock(lockFileURL: lockURL)
            let second = LocalProxyLock(lockFileURL: lockURL)

            try first.acquire()

            do {
                try second.acquire()
                Issue.record("Expected the second holder to be rejected.")
            } catch let error as LocalProxyLockError {
                #expect(error == .alreadyLocked(lockURL))
            }

            #expect(!second.isHeld)
        }
    }

    @Test
    func releasingAllowsAnotherHolder() throws {
        try withTempDir { directory in
            let lockURL = directory.appending(path: "lock")
            let first = LocalProxyLock(lockFileURL: lockURL)
            let second = LocalProxyLock(lockFileURL: lockURL)

            try first.acquire()
            first.release()

            try second.acquire()
            #expect(second.isHeld)
        }
    }

    @Test
    func reacquiringSameInstanceIsIdempotent() throws {
        try withTempDir { directory in
            let lock = LocalProxyLock(lockFileURL: directory.appending(path: "lock"))

            try lock.acquire()
            try lock.acquire()

            #expect(lock.isHeld)

            lock.release()
            #expect(!lock.isHeld)

            lock.release()
            #expect(!lock.isHeld)
        }
    }
}
