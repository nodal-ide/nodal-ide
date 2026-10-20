import Darwin
import Foundation

protocol UnixSocketProbing: Sendable {
    func isConnectable(path: String, timeout: Duration) async -> Bool
}

/// Probes a Unix domain socket with a non-blocking connect and a bounded timeout. Used for php-fpm
/// readiness checks; it never binds or kills anything.
struct UnixSocketProbe: UnixSocketProbing {
    func isConnectable(path: String, timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.connect(path: path, timeout: timeout))
            }
        }
    }

    private static func connect(path: String, timeout: Duration) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !pathBytes.isEmpty, pathBytes.count < capacity else {
            return false
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = CChar(bitPattern: byte)
                }
                destination[pathBytes.count] = 0
            }
        }

        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(descriptor, socketAddress, length)
            }
        }
        if result == 0 {
            return true
        }
        guard errno == EINPROGRESS else {
            return false
        }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let milliseconds = Int32(max(1, min(timeout.timeInterval * 1000, 60000)))
        guard poll(&pollDescriptor, 1, milliseconds) > 0 else {
            return false
        }

        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 else {
            return false
        }
        return socketError == 0
    }
}
