import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation

@MainActor
protocol AssistantSelectionSource {
    var fileURL: URL? { get }
    var text: String { get }
    var languageID: String { get }
    var selectedRanges: [NSRange] { get }
    func languageZones(at location: Int) -> [AssistantLanguageZone]
}

@MainActor
enum AssistantSelectionBridge {
    static func snapshot(
        from source: any AssistantSelectionSource,
        workspaceRoot: URL
    ) -> AssistantSelectionSnapshot? {
        guard let fileURL = source.fileURL else { return nil }
        let text = source.text
        let nsText = text as NSString
        let validRanges = source.selectedRanges.filter { range in
            range.location != NSNotFound
                && range.location >= 0
                && range.length >= 0
                && NSMaxRange(range) <= nsText.length
        }
        guard !validRanges.isEmpty else { return nil }

        let ranges = validRanges
            .sorted { $0.location < $1.location }
            .map { range -> AssistantSelectionRange in
                let selectedText: String
                if range.length == 0 {
                    let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
                    selectedText = nsText.substring(with: lineRange)
                        .trimmingCharacters(in: .newlines)
                } else {
                    selectedText = nsText.substring(with: range)
                }
                return AssistantSelectionRange(
                    lineRange: lineRange(for: range, in: nsText),
                    text: selectedText,
                    zones: source.languageZones(at: range.location)
                )
            }
        let relativePath = AssistantPathUtilities.relativePath(for: fileURL, root: workspaceRoot)

        return AssistantSelectionSnapshot(
            fileURL: fileURL,
            relativePath: relativePath,
            languageID: source.languageID,
            ranges: ranges,
            isSecretPath: SecretRedactor.isSecretPath(relativePath)
        )
    }

    static func lineRange(for range: NSRange, in text: NSString) -> ClosedRange<Int> {
        let startLine = lineNumber(at: range.location, in: text)
        let endOffset = range.length > 0 ? max(range.location, NSMaxRange(range) - 1) : range.location
        let endLine = lineNumber(at: min(endOffset, max(0, text.length)), in: text)
        return min(startLine, endLine)...max(startLine, endLine)
    }

    static func lineNumber(at location: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 1 }
        let boundedLocation = max(0, min(location, text.length))
        var line = 1
        var index = 0
        while index < boundedLocation {
            if text.character(at: index) == 10 {
                line += 1
            }
            index += 1
        }
        return line
    }
}

@MainActor
struct LiveEditorSelectionSource: AssistantSelectionSource {
    private let instance: EditorInstance
    private let document: CodeFileDocument?

    init(instance: EditorInstance, document: CodeFileDocument?) {
        self.instance = instance
        self.document = document
    }

    var fileURL: URL? {
        instance.file.url
    }

    var text: String {
        if let controller = instance.rangeTranslator.controller {
            return controller.textView.string
        }
        return document?.content?.string ?? ""
    }

    var languageID: String {
        if let controller = instance.rangeTranslator.controller {
            return controller.language.id.rawValue
        }
        return document?.getLanguage().id.rawValue ?? "plaintext"
    }

    var selectedRanges: [NSRange] {
        if let controller = instance.rangeTranslator.controller,
           let selectionManager = controller.textView.selectionManager {
            return selectionManager.textSelections
                .map(\.range)
                .filter { $0.location != NSNotFound && $0.length > 0 }
                .sorted { $0.location < $1.location }
        }
        return instance.cursorPositions
            .map(\.range)
            .filter { $0.location != NSNotFound && $0.length > 0 }
    }

    func languageZones(at location: Int) -> [AssistantLanguageZone] {
        guard let controller = instance.rangeTranslator.controller else {
            return [AssistantLanguageZone(languageID: languageID, parentLanguageID: nil, sourceKey: nil, depth: 0)]
        }
        return controller.languageContexts(at: location).map { context in
            AssistantLanguageZone(
                languageID: context.languageID.rawValue,
                parentLanguageID: context.parentLanguageID?.rawValue,
                sourceKey: context.sourceKey,
                depth: context.depth
            )
        }
    }
}
