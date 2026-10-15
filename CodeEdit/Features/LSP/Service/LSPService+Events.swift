//
//  LSPService+Events.swift
//  CodeEdit
//
//  Created by Abe Malla on 6/1/24.
//

import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol

extension LSPService {
    func startListeningToEvents(for key: ClientKey) {
        guard let languageClient = languageClients[key] else {
            logger.error("Language client not found for \(key.languageId.rawValue)")
            return
        }

        // Create a new Task to listen to the events
        let task = Task.detached { [weak self] in
            for await event in languageClient.lspInstance.eventSequence {
                await self?.handleEvent(event, for: key)
            }
        }
        eventListeningTasks[key] = task
    }

    func stopListeningToEvents(for key: ClientKey) {
        if let task = eventListeningTasks[key] {
            task.cancel()
            eventListeningTasks.removeValue(forKey: key)
        }
    }

    private func handleEvent(_ event: ServerEvent, for key: ClientKey) {
        guard let client = languageClient(for: key.languageId, workspacePath: key.workspacePath) else {
            return
        }

        switch event {
        case let .request(_, request):
            handleRequest(request, client: client)
        case let .notification(notification):
            handleNotification(notification, client: client)
        case let .error(error):
            logger.warning("Error from server \(key.languageId.rawValue, privacy: .public): \(error)")
        }
    }

    private func handleRequest(_ request: ServerRequest, client: LanguageServerType) {
        // TODO: Handle Requests
        switch request {
            //        case let .workspaceConfiguration(params, _):
            //            print("workspaceConfiguration: \(params)")
            //        case let .workspaceFolders(handler):
            //            print("workspaceFolders: \(String(describing: handler))")
            //        case let .workspaceApplyEdit(params, _):
            //            print("workspaceApplyEdit: \(params)")
//        case let .clientRegisterCapability(params, _):
//            print("clientRegisterCapability: \(params)")
//        case let .clientUnregisterCapability(params, _):
//            print("clientUnregisterCapability: \(params)")
            //        case let .workspaceCodeLensRefresh(handler):
            //            print("workspaceCodeLensRefresh: \(String(describing: handler))")
//        case let .workspaceSemanticTokenRefresh(handler):
//            print("Refresh semantic tokens!", handler)
            //        case let .windowShowMessageRequest(params, _):
            //            print("windowShowMessageRequest: \(params)")
            //        case let .windowShowDocument(params, _):
            //            print("windowShowDocument: \(params)")
            //        case let .windowWorkDoneProgressCreate(params, _):
            //            print("windowWorkDoneProgressCreate: \(params)")
        default:
            return
        }
    }

    private func handleNotification(_ notification: ServerNotification, client: LanguageServerType) {
        switch notification {
        case let .windowLogMessage(message):
            client.logContainer.appendLog(message)
        case let .textDocumentPublishDiagnostics(params):
            handlePublishDiagnostics(params)
//        case let .windowShowMessage(params):
//            print("windowShowMessage \(params.type)\n```\n\(params.message)\n```\n")
            //        case let .textDocumentPublishDiagnostics(params):
            //            print("textDocumentPublishDiagnostics: \(params)")
//        case let .telemetryEvent(params):
//            print("telemetryEvent: \(params)")
            //        case let .protocolCancelRequest(params):
            //            print("protocolCancelRequest: \(params)")
//        case let .protocolProgress(params):
//            print("protocolProgress: \(params)")
//        case let .protocolLogTrace(params):
//            print("protocolLogTrace: \(params)")
        default:
            return
        }
    }

    /// Handles push diagnostics (`textDocument/publishDiagnostics`), which servers like
    /// `typescript-language-server` use instead of pull diagnostics.
    private func handlePublishDiagnostics(_ params: PublishDiagnosticsParams) {
        guard let url = URL(string: params.uri) else { return }
        let content = (NSDocumentController.shared.document(for: url) as? CodeFileDocument)?.content?.string
        let diagnostics = params.diagnostics.map { diagnostic -> EditorDiagnostic in
            let range = content.flatMap { Self.nsRange(for: diagnostic.range, in: $0) }
                ?? NSRange(location: 0, length: 0)
            return EditorDiagnostic(
                range: range,
                severity: Self.severity(diagnostic.severity),
                message: diagnostic.message,
                line: diagnostic.range.start.line + 1
            )
        }
        DiagnosticsStore.shared.update(file: url, diagnostics: diagnostics)
    }

    private static func severity(_ severity: DiagnosticSeverity?) -> EditorDiagnosticSeverity {
        switch severity {
        case .error: return .error
        case .warning: return .warning
        case .information: return .info
        case .hint: return .hint
        case .none: return .error
        }
    }

    /// Converts an LSP range to an `NSRange` using the document's current text.
    private static func nsRange(for range: LSPRange, in content: String) -> NSRange? {
        let lineStarts = lineStartOffsets(in: content)
        guard let start = offset(for: range.start, lineStarts: lineStarts) else { return nil }
        let end = offset(for: range.end, lineStarts: lineStarts) ?? start
        let nsString = content as NSString
        let clampedStart = min(max(start, 0), nsString.length)
        let clampedLength = min(max(end - start, 0), nsString.length - clampedStart)
        return NSRange(location: clampedStart, length: clampedLength)
    }

    private static func offset(for position: Position, lineStarts: [Int]) -> Int? {
        guard position.line >= 0, position.line < lineStarts.count else { return nil }
        return lineStarts[position.line] + position.character
    }

    private static func lineStartOffsets(in string: String) -> [Int] {
        var offsets = [0]
        let nsString = string as NSString
        var index = 0
        while index < nsString.length {
            if nsString.character(at: index) == 0x0A {
                offsets.append(index + 1)
            }
            index += 1
        }
        return offsets
    }
}
