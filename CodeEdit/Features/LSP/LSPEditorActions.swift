//
//  LSPEditorActions.swift
//  CodeEdit
//
//  Editor commands backed by the language server: format document/selection and rename symbol.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// Menu/command actions that drive the active editor's language server.
@MainActor
enum LSPEditorActions {

    // MARK: - Formatting

    static func formatDocument(workspace: WorkspaceDocument?) {
        guard let context = activeContext(workspace: workspace) else { return }
        Task {
            let options = formattingOptions()
            guard let edits = try? await context.server.requestFormatting(
                for: context.fileURL.lspURI,
                withFormat: options
            ), !edits.isEmpty else {
                return
            }
            apply(edits, to: context.controller.textView)
        }
    }

    static func formatSelection(workspace: WorkspaceDocument?) {
        guard let context = activeContext(workspace: workspace),
              let selected = selectedLSPRange(in: context.controller.textView),
              selected.start != selected.end else {
            return
        }
        Task {
            let options = formattingOptions()
            guard let edits = try? await context.server.requestRangeFormatting(
                for: context.fileURL.lspURI,
                selected,
                withFormat: options
            ), !edits.isEmpty else {
                return
            }
            apply(edits, to: context.controller.textView)
        }
    }

    /// Formats a document's content in place before it is saved (format on save). Edits are applied
    /// bottom-to-top, and the content is only replaced if formatting actually changed it.
    static func formatForSave(document: CodeFileDocument, url: URL) async {
        guard let language = document.getLanguage().lspLanguage,
              let lsp = ServiceContainer.resolve(.singleton, LSPService.self) else {
            return
        }
        let workspacePath = document.findWorkspace()?.fileURL?.absolutePath ?? ""
        guard let server = lsp.languageClient(for: language, workspacePath: workspacePath),
              let edits = try? await server.requestFormatting(
                for: url.lspURI,
                withFormat: formattingOptions()
              ), !edits.isEmpty else {
            return
        }

        guard let content = document.content else { return }
        let original = content.string
        let updated = apply(edits, to: original)
        guard updated != original else { return }
        content.replaceCharacters(in: NSRange(location: 0, length: content.length), with: updated)
        document.updateChangeCount(.changeDone)
    }

    // MARK: - Rename

    static func renameSymbol(workspace: WorkspaceDocument?) {
        guard let workspace, let context = activeContext(workspace: workspace),
              let position = position(in: context.controller.textView) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename Symbol"
        alert.informativeText = "Enter the new name."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        Task {
            guard let edit = try? await context.server.requestRename(
                for: context.fileURL.lspURI,
                position: position,
                newName: newName
            ) else {
                return
            }
            apply(edit, workspace: workspace, activeFileURL: context.fileURL, controller: context.controller)
        }
    }

    // MARK: - Call hierarchy

    /// Prepares a call hierarchy at the cursor and returns the items (usually one) it applies to.
    static func prepareCallHierarchy(workspace: WorkspaceDocument?) async -> [CallHierarchyEntry] {
        guard let workspace,
              let context = activeContext(workspace: workspace),
              let position = position(in: context.controller.textView) else {
            return []
        }
        guard let items = try? await context.server.requestPrepareCallHierarchy(
            for: context.fileURL.lspURI,
            position: position
        ) else {
            return []
        }
        return items.map(callHierarchyEntry(from:))
    }

    /// Fetches the incoming or outgoing calls for a prepared call-hierarchy entry.
    static func callHierarchyCalls(
        for entry: CallHierarchyEntry,
        direction: CallHierarchyDirection,
        workspace: WorkspaceDocument?
    ) async -> [CallHierarchyCall] {
        guard let server = activeContext(workspace: workspace)?.server else {
            return []
        }
        switch direction {
        case .incoming:
            guard let calls = try? await server.requestCallHierarchyIncomingCalls(entry.item) else {
                return []
            }
            return calls.map { call in
                CallHierarchyCall(
                    id: "in:\(call.from.uri):\(call.from.selectionRange.start.line):\(call.from.name)",
                    entry: callHierarchyEntry(from: call.from),
                    callRanges: call.fromRanges
                )
            }
        case .outgoing:
            guard let calls = try? await server.requestCallHierarchyOutgoingCalls(entry.item) else {
                return []
            }
            return calls.map { call in
                CallHierarchyCall(
                    id: "out:\(call.to.uri):\(call.to.selectionRange.start.line):\(call.to.name)",
                    entry: callHierarchyEntry(from: call.to),
                    callRanges: call.fromRanges
                )
            }
        }
    }

    private static func callHierarchyEntry(from item: CallHierarchyItem) -> CallHierarchyEntry {
        let start = item.selectionRange.start
        return CallHierarchyEntry(
            id: "\(item.uri):\(start.line):\(start.character):\(item.name)",
            name: item.name,
            detail: item.detail,
            kind: item.kind,
            fileURL: URL(string: item.uri),
            line: start.line,
            column: start.character,
            item: item
        )
    }

    // MARK: - References

    /// Finds references to the symbol at the cursor and returns result rows for the references panel.
    static func referenceItems(workspace: WorkspaceDocument?) async -> [PaletteItem] {
        guard let workspace, let context = activeContext(workspace: workspace),
              let position = position(in: context.controller.textView) else {
            return []
        }
        guard let locations = try? await context.server.requestFindReferences(
            for: context.fileURL.lspURI,
            position,
            true
        ) else {
            return []
        }
        let workspacePath = workspace.fileURL?.path
        return (locations ?? []).compactMap {
            referenceItem(for: $0, workspace: workspace, workspacePath: workspacePath)
        }
    }

    private static func referenceItem(
        for location: Location,
        workspace: WorkspaceDocument,
        workspacePath: String?
    ) -> PaletteItem? {
        guard let url = URL(string: location.uri) else { return nil }
        let line = location.range.start.line + 1
        let column = location.range.start.character + 1

        var title = url.lastPathComponent
        var range: NSRange?
        if let content = string(for: url, workspace: workspace),
           let nsRange = nsRange(from: location.range, in: content) {
            range = nsRange
            let symbol = (content as NSString).substring(with: nsRange)
            if !symbol.isEmpty, !symbol.contains("\n") {
                title = symbol
            } else {
                title = lineText(at: line - 1, in: content) ?? url.lastPathComponent
            }
        }

        var subtitle = "\(url.lastPathComponent):\(line):\(column)"
        if let workspacePath, url.path.hasPrefix(workspacePath + "/") {
            subtitle = url.path
                .replacingOccurrences(of: workspacePath + "/", with: "") + ":\(line):\(column)"
        }

        return PaletteItem(
            id: "ref:\(location.uri):\(line):\(column)",
            kind: .symbol,
            title: title,
            subtitle: subtitle,
            fileURL: url,
            range: range,
            commandID: nil,
            matchedCharacters: [],
            symbolKind: nil
        )
    }

    /// Returns the current text of a file, preferring an open document over disk.
    private static func string(for url: URL, workspace: WorkspaceDocument) -> String? {
        if let file = workspace.workspaceFileManager?.getFile(url.path)
                    ?? workspace.workspaceFileManager?.getFile(url.relativePath),
           let content = file.fileDocument?.content {
            return content.string
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func nsRange(from range: LSPRange, in string: String) -> NSRange? {
        let lineStarts = lineStartOffsets(in: string)
        guard let start = offset(for: range.start, lineStarts: lineStarts),
              let end = offset(for: range.end, lineStarts: lineStarts) else {
            return nil
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func offset(for position: Position, lineStarts: [Int]) -> Int? {
        guard position.line >= 0, position.line < lineStarts.count else { return nil }
        return lineStarts[position.line] + position.character
    }

    private static func lineText(at line: Int, in string: String) -> String? {
        let lineStarts = lineStartOffsets(in: string)
        guard line >= 0, line < lineStarts.count else { return nil }
        let ns = string as NSString
        let start = lineStarts[line]
        let end = line + 1 < lineStarts.count ? lineStarts[line + 1] : ns.length
        guard start <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: start, length: max(0, end - start)))
            .trimmingCharacters(in: .newlines)
    }

    // MARK: - Helpers

    private struct Context {
        let controller: TextViewController
        let fileURL: URL
        let server: LanguageServer<CodeFileDocument>
    }

    private static func activeContext(workspace: WorkspaceDocument?) -> Context? {
        guard let workspace,
              let tab = workspace.editorManager?.activeEditor.selectedTab,
              let controller = tab.rangeTranslator.controller,
              let document = tab.file.fileDocument,
              let language = document.getLanguage().lspLanguage,
              let lsp = ServiceContainer.resolve(.singleton, LSPService.self),
              let server = lsp.languageClient(for: language, workspacePath: workspace.fileURL?.absolutePath ?? "") else {
            return nil
        }
        let fileURL = document.fileURL ?? tab.file.url
        return Context(controller: controller, fileURL: fileURL, server: server)
    }

    private static func formattingOptions() -> FormattingOptions {
        let textEditing = Settings.shared.preferences.textEditing
        let tabSize = max(1, textEditing.defaultTabWidth)
        return FormattingOptions(tabSize: tabSize, insertSpaces: textEditing.indentOption.indentType == .spaces)
    }

    private static func position(in textView: TextView) -> Position? {
        let selected = textView.selectionManager?.textSelections.first?.range ?? NSRange(location: 0, length: 0)
        return textView.lspRangeFrom(nsRange: selected)?.start
    }

    private static func selectedLSPRange(in textView: TextView) -> LSPRange? {
        let selected = textView.selectionManager?.textSelections.first?.range ?? NSRange(location: 0, length: 0)
        return textView.lspRangeFrom(nsRange: selected)
    }

    /// Applies LSP text edits to a text view (bottom-to-top so offsets stay valid).
    private static func apply(_ edits: [TextEdit], to textView: TextView) {
        let resolved = edits.compactMap { edit -> (NSRange, String)? in
            guard let range = textView.nsRange(fromLSP: edit.range) else { return nil }
            return (range, edit.newText)
        }.sorted { $0.0.location > $1.0.location }
        for (range, text) in resolved {
            textView.replaceCharacters(in: range, with: text)
        }
    }

    /// Applies a workspace edit (rename): edits open documents in memory, otherwise writes to disk.
    private static func apply(
        _ edit: WorkspaceEdit,
        workspace: WorkspaceDocument,
        activeFileURL: URL,
        controller: TextViewController
    ) {
        guard let changes = edit.changes else { return }
        for (uri, edits) in changes {
            guard let url = URL(string: uri) else { continue }
            if url.standardizedFileURL == activeFileURL.standardizedFileURL {
                apply(edits, to: controller.textView)
            } else if let file = workspace.workspaceFileManager?.getFile(url.path)
                        ?? workspace.workspaceFileManager?.getFile(url.relativePath),
                      let document = file.fileDocument,
                      let content = document.content {
                let updated = apply(edits, to: content.string)
                content.replaceCharacters(in: NSRange(location: 0, length: content.length), with: updated)
                document.updateChangeCount(.changeDone)
            } else {
                guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let updated = apply(edits, to: original)
                try? updated.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Applies LSP text edits to a string and returns the result.
    private static func apply(_ edits: [TextEdit], to string: String) -> String {
        let lineStarts = lineStartOffsets(in: string)
        func offset(_ position: Position) -> Int? {
            guard position.line >= 0, position.line < lineStarts.count else { return nil }
            return lineStarts[position.line] + position.character
        }
        let result = NSMutableString(string: string)
        let resolved = edits.compactMap { edit -> (NSRange, String)? in
            guard let start = offset(edit.range.start), let end = offset(edit.range.end) else { return nil }
            return (NSRange(location: start, length: max(0, end - start)), edit.newText)
        }.sorted { $0.0.location > $1.0.location }
        for (range, text) in resolved where NSMaxRange(range) <= result.length {
            result.replaceCharacters(in: range, with: text)
        }
        return result as String
    }

    private static func lineStartOffsets(in string: String) -> [Int] {
        let ns = string as NSString
        var starts = [0]
        var index = 0
        while index < ns.length {
            if ns.character(at: index) == 0x0A {
                starts.append(index + 1)
            }
            index += 1
        }
        return starts
    }
}
