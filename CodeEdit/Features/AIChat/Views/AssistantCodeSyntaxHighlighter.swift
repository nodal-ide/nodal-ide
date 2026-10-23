//
//  AssistantCodeSyntaxHighlighter.swift
//  CodeEdit
//

import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import SwiftTreeSitter

@MainActor
enum AssistantCodeSyntaxHighlighter {
    static func language(
        for label: String?,
        catalog: LanguageCatalog = .builtIn
    ) -> CodeLanguage? {
        guard var value = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else { return nil }

        if value.hasPrefix("language-") {
            value.removeFirst("language-".count)
        }
        if value.hasPrefix(".") {
            value.removeFirst()
        }
        guard !value.isEmpty,
              value != "text",
              value != "plaintext",
              value != "plain"
        else { return nil }

        return catalog.language(forIdentifier: value)
            ?? catalog.language(forFileExtension: value)
            ?? catalog.language(forFileName: value)
    }

    static func highlight(
        _ text: String,
        language: CodeLanguage,
        theme: EditorTheme,
        font: NSFont
    ) -> AttributedString? {
        guard !text.isEmpty,
              let parserLanguage = language.language,
              let query = query(for: language, parserLanguage: parserLanguage)
        else { return nil }

        do {
            let parser = Parser()
            try parser.setLanguage(parserLanguage)
            guard let tree = parser.parse(text) else { return nil }

            var ranges: [NSRange: Int] = [:]
            let captures = query.execute(in: tree)
                .resolve(with: .init(string: text))
                .flatMap(\.captures)
                .reversed()
                .compactMap { capture -> (NSRange, CaptureName)? in
                    let range = capture.range
                    let index = capture.index
                    if let existingLevel = ranges[range], existingLevel <= index {
                        return nil
                    }
                    guard let name = CaptureName.fromString(capture.name) else {
                        return nil
                    }
                    ranges[range] = index
                    return (range, name)
                }

            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: theme.text.color
                ]
            )
            for (range, capture) in captures {
                let style = attribute(for: capture, in: theme)
                attributed.setAttributes(
                    [
                        .font: styledFont(base: font, style: style),
                        .foregroundColor: style.color
                    ],
                    range: range
                )
            }
            return AttributedString(attributed)
        } catch {
            return nil
        }
    }

    private static func query(
        for language: CodeLanguage,
        parserLanguage: Language
    ) -> Query? {
        if let query = TreeSitterModel.shared.query(for: language.id) {
            return query
        }
        guard let querySet = language.querySet else { return nil }
        var sources = [querySet.highlights]
        if let parent = querySet.parentHighlights {
            sources.append(parent)
        }
        let source = sources
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        guard !source.isEmpty else { return nil }
        return try? Query(language: parserLanguage, data: Data(source.utf8))
    }

    private static func attribute(
        for capture: CaptureName,
        in theme: EditorTheme
    ) -> EditorTheme.Attribute {
        switch capture {
        case .include, .constructor, .keyword, .boolean, .repeat, .conditional, .tag,
             .variableBuiltin, .keywordReturn, .keywordFunction:
            return theme.keywords
        case .comment:
            return theme.comments
        case .variable, .property, .parameter:
            return theme.variables
        case .function, .method:
            return theme.commands
        case .number, .float:
            return theme.numbers
        case .string:
            return theme.strings
        case .character:
            return theme.characters
        case .type:
            return theme.types
        case .typeAlternate, .operator:
            return theme.attributes
        case .constant:
            return theme.values
        }
    }

    private static func styledFont(base: NSFont, style: EditorTheme.Attribute) -> NSFont {
        var font = base
        if style.bold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if style.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}
