import Foundation
import Network

private final class RelayConnectionPair {
    let incoming: NWConnection
    let outgoing: NWConnection
    var onClose: (() -> Void)?
    private(set) var didStartPiping = false
    private var completedDirections = 0
    private var isClosed = false

    init(incoming: NWConnection, outgoing: NWConnection) {
        self.incoming = incoming
        self.outgoing = outgoing
    }

    func startPiping() -> Bool {
        guard !didStartPiping else {
            return false
        }
        didStartPiping = true
        return true
    }

    func noteCompletedDirection() -> Bool {
        completedDirections += 1
        return completedDirections >= 2
    }

    func close() {
        guard !isClosed else {
            return
        }
        isClosed = true
        incoming.cancel()
        outgoing.cancel()
        onClose?()
    }
}

final class RelayEngine: @unchecked Sendable {
    private struct PendingListener {
        let listener: NWListener
        let port: Int
        let address: String
    }

    private let configuration: RelayConfiguration
    private let queue = DispatchQueue(label: "do.upper.codeedit.local-relay", qos: .userInitiated)
    private var pendingListeners: [PendingListener] = []
    private var readyListenerIDs: Set<ObjectIdentifier> = []
    private var listeners: [NWListener] = []
    private var connections: [UUID: RelayConnectionPair] = [:]
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var isRunning = false
    private var isStopping = false

    init(configuration: RelayConfiguration) {
        self.configuration = configuration
    }

    func start() async throws {
        try configuration.validate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard !self.isRunning, self.startContinuation == nil else {
                    continuation.resume(throwing: RelayError.alreadyRunning)
                    return
                }
                self.startContinuation = continuation
                do {
                    try self.beginStart()
                } catch {
                    self.failStart(error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.isStopping = true
                self.cancelAllListeners()
                let pairs = Array(self.connections.values)
                self.connections.removeAll()
                pairs.forEach { $0.close() }
                self.isRunning = false
                self.finishStart(.failure(RelayError.cancelled))
                continuation.resume()
            }
        }
    }

    private func beginStart() throws {
        isStopping = false
        readyListenerIDs.removeAll()
        let specs: [(listen: Int, target: Int)] = [
            (configuration.httpListenPort, configuration.httpTargetPort),
            (configuration.httpsListenPort, configuration.httpsTargetPort)
        ]
        for spec in specs {
            for address in ["127.0.0.1", "::1"] {
                pendingListeners.append(try makeListener(spec: spec, address: address))
            }
        }
        for pending in pendingListeners {
            start(pending)
        }
    }

    private func makeListener(spec: (listen: Int, target: Int), address: String) throws -> PendingListener {
        guard let port = NWEndpoint.Port(rawValue: UInt16(spec.listen)) else {
            throw RelayError.invalidPort(spec.listen)
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, targetPort: spec.target)
        }
        return PendingListener(listener: listener, port: spec.listen, address: address)
    }

    private func start(_ pending: PendingListener) {
        let id = ObjectIdentifier(pending.listener)
        pending.listener.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                self?.handle(state, listenerID: id, port: pending.port, address: pending.address)
            }
        }
        pending.listener.start(queue: queue)
    }

    private func handle(
        _ state: NWListener.State,
        listenerID: ObjectIdentifier,
        port: Int,
        address: String
    ) {
        if isStopping {
            return
        }
        switch state {
        case .ready:
            readyListenerIDs.insert(listenerID)
            if readyListenerIDs.count == pendingListeners.count {
                listeners = pendingListeners.map(\.listener)
                pendingListeners.removeAll()
                isRunning = true
                finishStart(.success(()))
            }
        case .failed(let error):
            failStart(RelayError.bindFailed(port: port, address: address, reason: error.localizedDescription))
        case .cancelled:
            if !isRunning, startContinuation != nil {
                failStart(RelayError.bindFailed(port: port, address: address, reason: "The listener was cancelled."))
            }
        case .waiting(let error):
            if !isRunning, startContinuation != nil {
                failStart(RelayError.bindFailed(port: port, address: address, reason: error.localizedDescription))
            }
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func accept(_ incoming: NWConnection, targetPort: Int) {
        guard !isStopping, let port = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
            incoming.cancel()
            return
        }
        let outgoing = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let pair = RelayConnectionPair(incoming: incoming, outgoing: outgoing)
        let id = UUID()
        connections[id] = pair
        pair.onClose = { [weak self] in
            self?.connections.removeValue(forKey: id)
        }
        pair.incoming.stateUpdateHandler = { [weak pair] state in
            switch state {
            case .failed, .cancelled:
                pair?.close()
            default:
                break
            }
        }
        pair.outgoing.stateUpdateHandler = { [weak self, weak pair] state in
            switch state {
            case .ready:
                if let pair {
                    self?.beginPiping(pair)
                }
            case .failed, .cancelled:
                pair?.close()
            default:
                break
            }
        }
        pair.incoming.start(queue: queue)
        pair.outgoing.start(queue: queue)
    }

    private func beginPiping(_ pair: RelayConnectionPair) {
        guard pair.startPiping() else {
            return
        }
        pipe(from: pair.incoming, to: pair.outgoing, pair: pair)
        pipe(from: pair.outgoing, to: pair.incoming, pair: pair)
    }

    private func pipe(from source: NWConnection, to destination: NWConnection, pair: RelayConnectionPair) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        pair.close()
                    } else if isComplete {
                        self.finish(destination, pair: pair)
                    } else {
                        self.pipe(from: source, to: destination, pair: pair)
                    }
                })
            } else if isComplete {
                self.finish(destination, pair: pair)
            } else if error != nil {
                pair.close()
            } else {
                self.pipe(from: source, to: destination, pair: pair)
            }
        }
    }

    private func finish(_ destination: NWConnection, pair: RelayConnectionPair) {
        destination.send(
            content: nil,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { error in
                if error != nil || pair.noteCompletedDirection() {
                    pair.close()
                }
            }
        )
    }

    private func failStart(_ error: any Error) {
        cancelAllListeners()
        isRunning = false
        finishStart(.failure(error))
    }

    private func cancelAllListeners() {
        pendingListeners.forEach {
            $0.listener.stateUpdateHandler = nil
            $0.listener.cancel()
        }
        pendingListeners.removeAll()
        readyListenerIDs.removeAll()
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
    }

    private func finishStart(_ result: Result<Void, any Error>) {
        guard let continuation = startContinuation else {
            return
        }
        startContinuation = nil
        continuation.resume(with: result)
    }
}
