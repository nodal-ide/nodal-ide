//
//  LSPService.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/7/24.
//

import AppKit
import os.log
import JSONRPC
import SwiftUI
import Foundation
import LanguageClient
import LanguageServerProtocol
import CodeEditLanguages

/// `LSPService` is a service class responsible for managing the lifecycle and event handling
/// of Language Server Protocol (LSP) clients within the CodeEdit application. It handles the initialization,
/// communication, and termination of language servers, ensuring that code assistance features
/// such as code completion, diagnostics, and more are available for various programming languages.
///
/// This class uses Swift's concurrency model to manage background tasks and event streams
/// efficiently. Each language server runs in its own asynchronous task, listening for events and
/// handling them as they occur. The `LSPService` class also provides functionality to start
/// and stop individual language servers, as well as to stop all running servers.
///
/// ## Example Usage
///
/// ```swift
/// @Service var lspService
///
/// try await lspService.startServer(
///    for: .python,
///    projectURL: projectURL,
///    workspaceFolders: workspaceFolders
/// )
/// try await lspService.stopServer(for: .python)
/// ```
///
/// ## Completion Example
///
/// ```swift
/// func testCompletion() async throws {
///     do {
///         guard var languageClient = self.languageClient(for: .python) else {
///             print("Failed to get client")
///             throw LSPServiceError.languageClientNotFound
///         }
///
///         let testFilePathStr = ""
///         let testFileURL = URL(fileURLWithPath: testFilePathStr)
///
///         // Tell server we opened a document
///         _ = await languageClient.addDocument(testFileURL)
///
///         // Completion example
///         let textPosition = Position(line: 32, character: 18)  // Lines and characters start at 0
///         let completions = try await languageClient.requestCompletion(
///             document: testFileURL.lspURI,
///             position: textPosition
///         )
///         switch completions {
///         case .optionA(let completionItems):
///             // Handle the case where completions is an array of CompletionItem
///             print("\n*******\nCompletion Items:\n*******\n")
///             for item in completionItems {
///                 let textEdits = LSPCompletionItemsUtil.getCompletionItemEdits(
///                     startPosition: textPosition,
///                     item: item
///                 )
///                 for edit in textEdits {
///                     print(edit)
///                 }
///             }
///
///         case .optionB(let completionList):
///             // Handle the case where completions is a CompletionList
///             print("\n*******\nCompletion Items:\n*******\n")
///             for item in completionList.items {
///                 let textEdits = LSPCompletionItemsUtil.getCompletionItemEdits(
///                     startPosition: textPosition,
///                     item: item
///                 )
///                 for edit in textEdits {
///                     print(edit)
///                 }
///             }
///
///             print(completionList.items[0])
///
///         case .none:
///             print("No completions found")
///         }
///
///         // Close the document
///         _ = await languageClient.closeDocument(testFilePathStr)
///     } catch {
///         print(error)
///     }
/// }
/// ```
@MainActor
final class LSPService: ObservableObject {
    typealias LanguageServerType = LanguageServer<CodeFileDocument>

    let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "LSPService")

    struct ClientKey: Hashable, Equatable {
        let languageId: LanguageIdentifier
        let workspacePath: String

        init(_ languageId: LanguageIdentifier, _ workspacePath: String) {
            self.languageId = languageId
            self.workspacePath = workspacePath
        }
    }

    /// Holds the active language clients
    @Published var languageClients: [ClientKey: LanguageServerType] = [:]
    /// Holds the language server configurations for all the installed language servers
    var languageConfigs: [LanguageIdentifier: LanguageServerBinary] = [:]
    /// Holds all the event listeners for each active language client
    var eventListeningTasks: [ClientKey: Task<Void, Never>] = [:]

    /// Language/workspace combinations whose server failed to start (avoids respawning on every tab).
    var failedClientKeys: Set<ClientKey> = []

    /// In-flight server starts, keyed by client key (dedupes concurrent starts).
    var startingTasks: [ClientKey: Task<LanguageServerType, Error>] = [:]

    @AppSettings(\.developerSettings.lspBinaries)
    var lspBinaries

    /// Registry-installed language servers.
    @AppSettings(\.languageServers.installedLanguageServers)
    var installedServers

    /// Language identifiers handled by a native, in-process implementation. No language server is started for these.
    @AppSettings(\.developerSettings.internalLanguages)
    var internalLanguages

    @Environment(\.openWindow)
    private var openWindow

    init() {
        reloadConfigurations()

        NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didOpenNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let document = notification.object as? CodeFileDocument else { return }
                self.openDocument(document)
            }
        }

        NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let url = notification.object as? URL else { return }
                self.closeDocument(url)
            }
        }
    }

    /// Gets the language server for the specified language and workspace.
    func server(for languageId: LanguageIdentifier, workspacePath: String) -> InitializingServer? {
        return languageClients[ClientKey(languageId, workspacePath)]?.lspInstance
    }

    /// Whether a language server is available for the given language, either configured (installed) or already running.
    ///
    /// Used to decide whether it's worth requesting LSP-backed features (e.g. semantic token highlighting). If no
    /// server exists we skip those providers entirely instead of waiting on data that will never arrive.
    func hasServer(for languageId: LanguageIdentifier) -> Bool {
        languageConfigs[languageId] != nil
            || languageClients.keys.contains(where: { $0.languageId == languageId })
    }

    /// Whether the given language is handled by a native, in-process implementation rather than a language server.
    func usesInternalLanguage(_ languageId: LanguageIdentifier) -> Bool {
        internalLanguages.contains(languageId.rawValue)
    }

    /// Gets the language client for the specified language
    func languageClient(for languageId: LanguageIdentifier, workspacePath: String) -> LanguageServerType? {
        return languageClients[ClientKey(languageId, workspacePath)]
    }

    func languageClient(forDocument url: URL) -> LanguageServerType? {
        languageClients.values.first(where: { $0.openFiles.document(for: url.lspURI) != nil })
    }

    // MARK: - Start Server

    /// Given a language and workspace path, will attempt to start the language server
    /// - Parameters:
    ///   - languageId: The ID of the language server to start.
    ///   - workspacePath: The workspace this language server is being used in.
    /// - Returns: The new language server.
    func startServer(
        for languageId: LanguageIdentifier,
        workspacePath: String
    ) async throws -> LanguageServerType {
        let key = ClientKey(languageId, workspacePath)
        // Reuse an already-running server, or await an in-flight start (avoids spawning two processes when
        // multiple documents open at once, e.g. restored tabs).
        if let existing = languageClients[key] {
            return existing
        }
        if let inFlight = startingTasks[key] {
            return try await inFlight.value
        }
        guard let serverBinary = languageConfigs[languageId] else {
            logger.error("Couldn't find language sever binary for \(languageId.rawValue)")
            throw LSPError.binaryNotFound
        }

        logger.info("Starting \(languageId.rawValue) language server")
        let task = Task {
            try await LanguageServerType.createServer(
                for: languageId,
                with: serverBinary,
                workspacePath: workspacePath
            )
        }
        startingTasks[key] = task
        do {
            let server = try await task.value
            startingTasks[key] = nil
            languageClients[key] = server
            logger.info("Successfully started \(languageId.rawValue) language server")
            startListeningToEvents(for: key)
            return server
        } catch {
            startingTasks[key] = nil
            throw error
        }
    }

    // MARK: - Stop Servers

    /// Attempts to stop a running language server. Throws an error if the server is not found
    /// or if the language server throws an error while trying to shutdown.
    /// - Parameters:
    ///   - languageId: The ID of the language server to stop.
    ///   - workspacePath: The path of the workspace to stop the language server for.
    func stopServer(forLanguage languageId: LanguageIdentifier, workspacePath: String) async throws {
        guard let server = server(for: languageId, workspacePath: workspacePath) else {
            logger.error("Server not found for language \(languageId.rawValue) during stop operation")
            throw LSPServiceError.serverNotFound
        }
        do {
            try await server.shutdownAndExit()
        } catch {
            logger.error("Failed to stop server for language \(languageId.rawValue): \(error.localizedDescription)")
            throw error
        }
        languageClients.removeValue(forKey: ClientKey(languageId, workspacePath))
        logger.info("Server stopped for language \(languageId.rawValue)")

        stopListeningToEvents(for: ClientKey(languageId, workspacePath))
    }

    /// Goes through all active language servers and attempts to shut them down.
    func stopAllServers() async {
        await withTaskGroup(of: Void.self) { group in
            for (key, server) in languageClients {
                group.addTask {
                    do {
                        try await server.shutdown()
                    } catch {
                        self.logger.warning("Shutting down \(key.languageId.rawValue): Error \(error)")
                    }
                }
            }
        }
        languageClients.removeAll()
        eventListeningTasks.forEach { (_, value) in
            value.cancel()
        }
        eventListeningTasks.removeAll()
    }

    /// Call this when a server is refusing to terminate itself. Sends the `SIGKILL` signal to all lsp processes.
    func killAllServers() {
        for (_, server) in languageClients {
            kill(server.pid, SIGKILL)
        }
    }
}

extension LSPService {
    func notifyToInstallLanguageServer(language lspLanguage: LanguageIdentifier) {
        // TODO: Re-Enable when this is more fleshed out (don't send duplicate notifications in a session)
        return
        // FIXME: Unreachable code - remove or re-enable when ready
        /*
        let lspLanguageTitle = lspLanguage.rawValue.capitalized
        let notificationTitle = "Install \(lspLanguageTitle) Language Server"
        // Make sure the user doesn't have the same existing notification
        guard !NotificationManager.shared.notifications.contains(where: { $0.title == notificationTitle }) else {
            return
        }

        NotificationManager.shared.post(
            iconSymbol: "arrow.down.circle",
            iconColor: .clear,
            title: notificationTitle,
            description: "Install the \(lspLanguageTitle) language server to enable code intelligence features.",
            actionButtonTitle: "Install"
        ) { [weak self] in
            // TODO: Warning:
            // Accessing Environment<OpenWindowAction>'s value outside of being installed on a View.
            // This will always read the default value and will not update
            self?.openWindow(sceneID: .settings)
        }
        */
    }
}

// MARK: - Errors

enum ServerManagerError: Error {
    case serverNotFound
    case serverStartFailed
    case serverStopFailed
    case languageClientNotFound
}
