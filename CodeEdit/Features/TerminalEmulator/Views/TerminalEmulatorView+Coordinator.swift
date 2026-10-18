//
//  TerminalEmulatorView+Coordinator.swift
//  CodeEditModules/TerminalEmulator
//
//  Created by Lukas Pistrol on 24.03.22.
//

import SwiftUI
import SwiftTerm

extension TerminalEmulatorView {
    final class Coordinator: NSObject, CELocalShellTerminalViewDelegate {
        private let terminalID: UUID
        public var onTitleChange: (_ title: String) -> Void
        public var onCwdChange: (URL?) -> Void
        public var onCommandStart: () -> Void
        public var onCommandFinish: (Int?) -> Void
        public var onOpenLink: (String) -> Void

        var mode: TerminalMode

        init(
            terminalID: UUID,
            mode: TerminalMode,
            onTitleChange: @escaping (_ title: String) -> Void,
            onCwdChange: @escaping (URL?) -> Void,
            onCommandStart: @escaping () -> Void,
            onCommandFinish: @escaping (Int?) -> Void,
            onOpenLink: @escaping (String) -> Void
        ) {
            self.terminalID = terminalID
            self.mode = mode
            self.onTitleChange = onTitleChange
            self.onCwdChange = onCwdChange
            self.onCommandStart = onCommandStart
            self.onCommandFinish = onCommandFinish
            self.onOpenLink = onOpenLink
            super.init()
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            onOpenLink(link)
        }

        /// Parses our shell-integration command markers (`OSC 1337; CodeEdit=start` / `CodeEdit=exit;<code>`).
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
            guard let text = String(bytes: content, encoding: .utf8),
                  text.hasPrefix("CodeEdit=") else {
                return
            }
            let payload = String(text.dropFirst("CodeEdit=".count))
            let parts = payload.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard let kind = parts.first else { return }
            switch kind {
            case "start":
                onCommandStart()
            case "exit":
                onCommandFinish(parts.count > 1 ? Int(parts[1]) : nil)
            default:
                break
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let directory, !directory.isEmpty else { return }
            let url: URL?
            if directory.hasPrefix("file://") {
                if let parsed = URL(string: directory), !parsed.path.isEmpty {
                    url = parsed
                } else {
                    // Handle unescaped paths with spaces: `file://host/path with spaces`.
                    let withoutScheme = String(directory.dropFirst("file://".count))
                    if let slash = withoutScheme.firstIndex(of: "/") {
                        url = URL(filePath: String(withoutScheme[slash...]))
                    } else {
                        url = nil
                    }
                }
            } else {
                url = URL(filePath: directory)
            }
            onCwdChange(url)
        }

        func sizeChanged(source: CETerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: CETerminalView, title: String) {
            onTitleChange(title)
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            guard let exitCode else {
                return
            }
            if case .shell = mode {
                source.feed(text: "Exit code: \(exitCode)\n\r\n")
                source.feed(text: "To open a new session, create a new terminal tab.")
                AppServices.terminalCache.removeCachedView(terminalID)
            }
        }
    }
}
