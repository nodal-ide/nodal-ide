import Darwin
import Foundation

/// Reads the identity and liveness of a process left behind by an earlier app session. Used before
/// reaping a stale php-fpm that still owns a site's Unix socket.
protocol PHPFPMProcessInspecting: Sendable {
    func isRunning(pid: Int32) -> Bool
    func executablePath(pid: Int32) -> String?
    func arguments(pid: Int32) -> [String]?
    func signal(_ signal: Int32, to pid: Int32) -> Bool
}

struct SystemPHPFPMProcessInspector: PHPFPMProcessInspecting {
    func isRunning(pid: Int32) -> Bool {
        guard pid > 0 else {
            return false
        }
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    func arguments(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return Self.arguments(fromProcArgs: buffer, size: size)
    }

    func signal(_ signal: Int32, to pid: Int32) -> Bool {
        Darwin.kill(pid, signal) == 0
    }

    private static func arguments(fromProcArgs buffer: [UInt8], size: Int) -> [String]? {
        guard size > MemoryLayout<Int32>.size else {
            return nil
        }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else {
            return nil
        }

        var offset = MemoryLayout<Int32>.size
        while offset < size, buffer[offset] != 0 {
            offset += 1
        }
        while offset < size, buffer[offset] == 0 {
            offset += 1
        }

        var result: [String] = []
        for _ in 0..<argc {
            let start = offset
            while offset < size, buffer[offset] != 0 {
                offset += 1
            }
            if let value = String(bytes: buffer[start..<offset], encoding: .utf8) {
                result.append(value)
            }
            offset += 1
        }
        return result
    }
}
