//
//  CodeFileLifecycleCoordinator.swift
//  CodeEdit
//
//  Owns the per-document side effects that `CodeFileView` used to perform in `init` (change-count
//  tracking, the debounced PHP symbol-index refresh, and starting the language server). Held as a
//  `@StateObject` so the subscriptions have a stable lifetime instead of being re-created per render.
//

import Combine
import Foundation

@MainActor
final class CodeFileLifecycleCoordinator: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    /// Starts observing the document. Idempotent, so it is safe to call from `onAppear`.
    func start(codeFile: CodeFileDocument, refreshSymbolIndex: Bool) {
        guard !started else { return }
        started = true

        codeFile
            .contentCoordinator
            .textUpdatePublisher
            .sink { [weak codeFile] _ in
                codeFile?.updateChangeCount(.changeDone)
            }
            .store(in: &cancellables)

        // Keep the workspace symbol index fresh while editing (debounced).
        if refreshSymbolIndex, let fileURL = codeFile.fileURL {
            codeFile
                .contentCoordinator
                .textUpdatePublisher
                .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
                .sink { [weak codeFile] _ in
                    guard let source = codeFile?.content?.string else { return }
                    PHPWorkspaceIndex.shared.refreshFromSource(file: fileURL, source: source)
                }
                .store(in: &cancellables)
        }
    }

    /// Ensures the language server starts for this document. Documents restored at launch may open before the
    /// workspace/configs are ready, so the `didOpen` notification alone can miss them.
    func ensureLanguageServerStarted(codeFile: CodeFileDocument) {
        guard codeFile.getLanguage().lspLanguage != nil,
              let lsp = ServiceContainer.resolve(.singleton, LSPService.self) else {
            return
        }
        lsp.openDocument(codeFile)
    }
}
