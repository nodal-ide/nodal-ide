//
//  LSPService+Documents.swift
//  CodeEdit
//
//  Opening/closing documents and workspaces against the active language servers.
//

import Foundation
import LanguageServerProtocol

extension LSPService {
    /// Notify all relevant language clients that a document was opened.
    /// - Note: Must be invoked after the contents of the file are available.
    /// - Parameter document: The code document that was opened.
    func openDocument(_ document: CodeFileDocument) {
        guard let workspace = document.findWorkspace(),
              let workspacePath = workspace.fileURL?.absolutePath,
              let lspLanguage = document.getLanguage().lspLanguage,
              !internalLanguages.contains(lspLanguage.rawValue) else {
            return
        }
        guard hasServer(for: lspLanguage) else { return }
        let key = ClientKey(lspLanguage, workspacePath)
        guard !failedClientKeys.contains(key) else { return }
        Task {
            let languageServer: LanguageServerType
            do {
                if let server = self.languageClients[key] {
                    languageServer = server
                } else {
                    languageServer = try await self.startServer(for: lspLanguage, workspacePath: workspacePath)
                }
            } catch {
                self.failedClientKeys.insert(key)
                notifyToInstallLanguageServer(language: lspLanguage)
                // swiftlint:disable:next line_length
                self.logger.error("Failed to start \(lspLanguage.rawValue) server for \(workspacePath, privacy: .private): \(error.localizedDescription)")
                return
            }
            do {
                try await languageServer.openDocument(document)
            } catch {
                let uri = document.languageServerURI
                // swiftlint:disable:next line_length
                self.logger.error("Failed to close document: \(uri ?? "<NO URI>", privacy: .private), language: \(lspLanguage.rawValue). Error \(error)")
            }
        }
    }

    /// Notify all relevant language clients that a document was closed.
    /// - Parameter url: The url of the document that was closed
    func closeDocument(_ url: URL) {
        guard let languageClient = languageClient(forDocument: url) else { return }
        Task {
            do {
                try await languageClient.closeDocument(url.lspURI)
            } catch {
                // swiftlint:disable:next line_length
                logger.error("Failed to close document: \(url.lspURI, privacy: .private), language: \(languageClient.languageId.rawValue). Error \(error)")
            }
        }
    }

    /// Close all language clients for a workspace.
    ///
    /// This is intentionally synchronous so we can exit from the workspace document's ``WorkspaceDocument/close()``
    /// method ASAP.
    ///
    /// Errors thrown in this method are logged and otherwise not handled.
    /// - Parameter workspacePath: The path of the workspace.
    func closeWorkspace(_ workspacePath: String) {
        Task {
            let clientKeys = self.languageClients.filter({ $0.key.workspacePath == workspacePath })
            for (key, languageClient) in clientKeys {
                do {
                    try await languageClient.shutdown()
                } catch {
                    logger.error("Failed to shutdown \(key.languageId.rawValue) Language Server: Error \(error)")
                }
            }
            for (key, _) in clientKeys {
                self.languageClients.removeValue(forKey: key)
            }
        }
    }
}
