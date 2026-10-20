import Foundation

@main
enum RelayMain {
    static func main() async {
        let engine = RelayEngine(configuration: .standard)
        do {
            try await engine.start()
        } catch {
            writeToStandardError("CodeEditRelay: \(error.localizedDescription)\n")
            exit(EXIT_FAILURE)
        }
        await RelaySignalWaiter().wait()
        await engine.stop()
    }

    private static func writeToStandardError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}

private final class RelaySignalWaiter {
    private var sources: [DispatchSourceSignal] = []
    private var didResume = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            for signalNumber in [SIGTERM, SIGINT] {
                signal(signalNumber, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
                source.setEventHandler { [weak self] in
                    guard let self, !self.didResume else {
                        return
                    }
                    self.didResume = true
                    self.sources.forEach { $0.cancel() }
                    continuation.resume()
                }
                source.resume()
                sources.append(source)
            }
        }
    }
}
