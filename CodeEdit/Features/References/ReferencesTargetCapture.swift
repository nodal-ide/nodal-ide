import Foundation
import CodeEditLanguages
import CodeEditLang
import CodeEditSourceEditor

@MainActor
enum ReferencesTargetCapture {
    enum Outcome {
        case captured(ReferenceQuery)
        case unavailable(String)
    }

    static func capture(in workspace: WorkspaceDocument) -> Outcome {
        guard let manager = workspace.editorManager,
              let tab = manager.activeEditor.selectedTab ?? manager.activeEditor.temporaryTab else {
            return .unavailable("Open a file to find references.")
        }
        guard let document = tab.file.fileDocument else {
            return .unavailable("Find references needs a text editor.")
        }

        let controller = tab.rangeTranslator.controller
        let source = controller?.textView.string ?? document.content?.string ?? ""
        let text = source as NSString
        guard text.length > 0 else { return .unavailable("The file is empty.") }

        let selections = selectionRanges(in: tab, controller: controller, textLength: text.length)
        guard let range = symbolRange(in: text, selections: selections) else {
            return .unavailable("Place the cursor on a symbol to find its references.")
        }

        let language = controller?.language
            ?? document.getLanguage(catalog: document.workspaceLanguageCatalog())
        let zone = controller?.languageContexts(at: range.location).first
            ?? LanguageZoneContext(languageID: language.id)

        return .captured(
            ReferenceQuery(
                target: ReferenceTarget(
                    identifier: text.substring(with: range),
                    fileURL: document.fileURL ?? tab.file.url,
                    range: range
                ),
                languageID: zone.languageID.rawValue,
                rootLanguageID: language.id.rawValue,
                zoneDepth: zone.depth,
                source: source,
                workspaceRoot: workspace.workspaceFileManager?.folderUrl ?? workspace.fileURL
            )
        )
    }

    static func symbolRange(in text: NSString, selections: [NSRange]) -> NSRange? {
        for selection in selections {
            if selection.length > 0 {
                guard let trimmed = trimmed(selection, in: text) else { continue }
                if !containsNewline(trimmed, in: text) { return trimmed }
                if let identifier = identifierRange(at: trimmed.location, in: text) { return identifier }
                continue
            }
            if let identifier = identifierRange(at: selection.location, in: text) { return identifier }
        }
        return nil
    }

    static func identifierRange(at offset: Int, in text: NSString) -> NSRange? {
        guard text.length > 0 else { return nil }
        var anchor = min(max(offset, 0), text.length - 1)
        if !isIdentifier(text.character(at: anchor)),
           anchor > 0,
           isIdentifier(text.character(at: anchor - 1)) {
            anchor -= 1
        }
        guard isIdentifier(text.character(at: anchor)) else { return nil }

        var start = anchor
        while start > 0, isIdentifier(text.character(at: start - 1)) { start -= 1 }
        var end = anchor
        while end < text.length, isIdentifier(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    static func isIdentifier(_ character: unichar) -> Bool {
        if character == 0x5F || character == 0x24 || character == 0x5C { return true }
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func selectionRanges(
        in tab: EditorInstance,
        controller: TextViewController?,
        textLength: Int
    ) -> [NSRange] {
        let positions = controller?.cursorPositions ?? tab.cursorPositions
        let selected = positions.map(\.range).filter {
            $0.location != NSNotFound && $0.length > 0 && NSMaxRange($0) <= textLength
        }
        if !selected.isEmpty { return selected }

        let carets = positions.map(\.range)
            .filter { $0.location != NSNotFound && $0.location <= textLength }
            .map { NSRange(location: $0.location, length: 0) }
        if !carets.isEmpty { return carets }

        return (controller?.textView.selectionManager?.textSelections.map(\.range) ?? [])
            .filter { $0.location != NSNotFound && NSMaxRange($0) <= textLength }
    }

    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange? {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isWhitespace(text.character(at: start)) { start += 1 }
        while end > start, isWhitespace(text.character(at: end - 1)) { end -= 1 }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func containsNewline(_ range: NSRange, in text: NSString) -> Bool {
        for index in range.location..<NSMaxRange(range) where isWhitespace(text.character(at: index)) {
            let character = text.character(at: index)
            if character == 0x0A || character == 0x0D { return true }
        }
        return false
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
