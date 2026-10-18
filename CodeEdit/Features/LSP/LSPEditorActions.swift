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
import os

private let lspEditorLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "LSPEditorActions")

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

    /// Requests and applies language-server "source" actions (e.g. organize imports) for the whole document.
    /// The first action with edits is applied bottom-to-top.
    static func organizeImports(workspace: WorkspaceDocument?) {
        guard let workspace, let context = activeContext(workspace: workspace) else { return }
        Task {
            let length = context.controller.textView.textStorage?.length ?? 0
            guard let range = context.controller.textView.lspRangeFrom(
                nsRange: NSRange(location: 0, length: length)
            ) else {
                return
            }
            let actionContext = CodeActionContext(
                diagnostics: [],
                only: [.SourceOrganizeImports, .Source]
            )
            guard let response = try? await context.server.requestCodeActions(
                for: context.fileURL.lspURI,
                range: range,
                context: actionContext
            ) else {
                return
            }
            for option in response {
                guard case .optionB(var action) = option else { continue }
                if action.edit == nil, action.data != nil,
                   let resolved = try? await context.server.requestCodeActionResolve(action) {
                    action = resolved
                }
                guard let edit = action.edit else { continue }
                apply(edit, workspace: workspace, activeFileURL: context.fileURL, controller: context.controller)
                return
            }
        }
    }

    /// Formats a document's content in place before it is saved (format on save). Edits are applied
    /// bottom-to-top, and the content is only replaced if formatting actually changed it.
    static func formatForSave(document: CodeFileDocument, url: URL) async {
        guard let language = document.getLanguage().lspLanguage else {
            return
        }
        let lsp = AppServices.lspService
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

    // MARK: - Helpers

    struct Context {
        let controller: TextViewController
        let fileURL: URL
        let server: LanguageServer<CodeFileDocument>
    }

    static func activeContext(workspace: WorkspaceDocument?) -> Context? {
        guard let workspace,
              let tab = workspace.editorManager?.activeEditor.selectedTab,
              let controller = tab.rangeTranslator.controller,
              let document = tab.file.fileDocument,
              let language = document.getLanguage().lspLanguage,
              let server = AppServices.lspService.languageClient(
                  for: language,
                  workspacePath: workspace.fileURL?.absolutePath ?? ""
              ) else {
            return nil
        }
        let fileURL = document.fileURL ?? tab.file.url
        return Context(controller: controller, fileURL: fileURL, server: server)
    }

    private static func formattingOptions() -> FormattingOptions {
        let textEditing = AppServices.settings.preferences.textEditing
        let tabSize = max(1, textEditing.defaultTabWidth)
        return FormattingOptions(tabSize: tabSize, insertSpaces: textEditing.indentOption.indentType == .spaces)
    }

    static func position(in textView: TextView) -> Position? {
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
                do {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    let message = "Failed to write LSP edits to \(url.path): \(error.localizedDescription)"
                    lspEditorLogger.error("\(message, privacy: .public)")
                }
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

    static func lineStartOffsets(in string: String) -> [Int] {
        let nsString = string as NSString
        var starts = [0]
        var index = 0
        while index < nsString.length {
            if nsString.character(at: index) == 0x0A {
                starts.append(index + 1)
            }
            index += 1
        }
        return starts
    }
}
