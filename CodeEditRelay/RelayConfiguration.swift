import Foundation

struct RelayConfiguration: Equatable, Sendable {
    static let httpInternalPort = 8080
    static let httpsInternalPort = 8443

    static let standard = RelayConfiguration(
        httpListenPort: 80,
        httpTargetPort: httpInternalPort,
        httpsListenPort: 443,
        httpsTargetPort: httpsInternalPort
    )

    let httpListenPort: Int
    let httpTargetPort: Int
    let httpsListenPort: Int
    let httpsTargetPort: Int

    var allPorts: [Int] {
        [httpListenPort, httpTargetPort, httpsListenPort, httpsTargetPort]
    }

    func validate() throws {
        for port in allPorts where !(1...65535).contains(port) {
            throw RelayError.invalidPort(port)
        }
    }
}

enum RelayError: Error, Equatable {
    case invalidPort(Int)
    case bindFailed(port: Int, address: String, reason: String)
    case alreadyRunning
    case cancelled
}

extension RelayError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "The relay port is out of range: \(port)."
        case let .bindFailed(port, address, reason):
            return "The relay could not bind \(address):\(port): \(reason)"
        case .alreadyRunning:
            return "The relay is already running."
        case .cancelled:
            return "The relay was cancelled."
        }
    }
}
