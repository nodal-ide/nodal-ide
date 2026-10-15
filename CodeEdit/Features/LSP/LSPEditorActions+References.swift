//
//  LSPEditorActions+References.swift
//  CodeEdit
//
//  "Find All References" results for the references panel.
//

import AppKit
import Foundation
import LanguageServerProtocol

extension LSPEditorActions {
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
        let nsString = string as NSString
        let start = lineStarts[line]
        let end = line + 1 < lineStarts.count ? lineStarts[line + 1] : nsString.length
        guard start <= nsString.length else { return nil }
        return nsString.substring(with: NSRange(location: start, length: max(0, end - start)))
            .trimmingCharacters(in: .newlines)
    }
}
