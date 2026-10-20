import Darwin
import Foundation

protocol PortProbing: Sendable {
    func isReachable(host: String, port: Int, timeout: Duration) async -> Bool
}

/// Probes a TCP port with a non-blocking connect and a bounded timeout. Used for readiness checks and
/// busy-port detection; it never binds or kills anything.
struct SocketPortProbe: PortProbing {
    func isReachable(host: String, port: Int, timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.connect(host: host, port: port, timeout: timeout))
            }
        }
    }

    private static func connect(host: String, port: Int, timeout: Duration) -> Bool {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var infoPointer: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &infoPointer) == 0, let info = infoPointer else {
            return false
        }
        defer { freeaddrinfo(infoPointer) }

        let descriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        if Darwin.connect(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
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
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return false
        }
        return socketError == 0
    }
}
