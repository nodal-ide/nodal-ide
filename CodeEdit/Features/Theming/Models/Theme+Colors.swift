import AppKit
import SwiftUI
import CodeEditLang
import CodeEditSourceEditor

extension ThemeDocument.Attributes {
    var swiftColor: Color {
        get { Color(hex: color) }
        set { color = newValue.hexString }
    }

    var nsColor: NSColor {
        get { NSColor(hex: color) }
        set { color = newValue.hexString }
    }
}

extension ThemeDocument.EditorColors {
    var editorTheme: EditorTheme {
        get {
            .init(
                text: .init(color: text.nsColor),
                insertionPoint: insertionPoint.nsColor,
                invisibles: .init(color: invisibles.nsColor),
                background: background.nsColor,
                lineHighlight: lineHighlight.nsColor,
                selection: selection.nsColor,
                keywords: .init(color: keywords.nsColor),
                commands: .init(color: commands.nsColor),
                types: .init(color: types.nsColor),
                attributes: .init(color: attributes.nsColor),
                variables: .init(color: variables.nsColor),
                values: .init(color: values.nsColor),
                numbers: .init(color: numbers.nsColor),
                strings: .init(color: strings.nsColor),
                characters: .init(color: characters.nsColor),
                comments: .init(color: comments.nsColor)
            )
        }
        set {
            text.nsColor = newValue.text.color
            insertionPoint.nsColor = newValue.insertionPoint
            invisibles.nsColor = newValue.invisibles.color
            background.nsColor = newValue.background
            lineHighlight.nsColor = newValue.lineHighlight
            selection.nsColor = newValue.selection
            keywords.nsColor = newValue.keywords.color
            commands.nsColor = newValue.commands.color
            types.nsColor = newValue.types.color
            attributes.nsColor = newValue.attributes.color
            variables.nsColor = newValue.variables.color
            values.nsColor = newValue.values.color
            numbers.nsColor = newValue.numbers.color
            strings.nsColor = newValue.strings.color
            characters.nsColor = newValue.characters.color
            comments.nsColor = newValue.comments.color
        }
    }
}
