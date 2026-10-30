import Foundation
import CodeEditLang

enum ThemeSource: Hashable {
    case bundled
    case user
    case extensionPack(id: String, name: String)

    var isBuiltIn: Bool {
        if case .bundled = self {
            return true
        }
        return false
    }

    var isEditable: Bool {
        if case .user = self {
            return true
        }
        return false
    }

    var packID: String? {
        if case let .extensionPack(id, _) = self {
            return id
        }
        return nil
    }

    var displayName: String {
        switch self {
        case .bundled:
            return "Bundled"
        case .user:
            return "Custom"
        case let .extensionPack(_, name):
            return name
        }
    }
}

struct Theme: Identifiable, Hashable {
    let id: String
    let source: ThemeSource
    let fileURL: URL?
    var document: ThemeDocument

    var name: String {
        get { document.name }
        set { document.name = newValue }
    }

    var displayName: String {
        get { document.displayName }
        set { document.displayName = newValue }
    }

    var author: String {
        get { document.author }
        set { document.author = newValue }
    }

    var license: String {
        get { document.license }
        set { document.license = newValue }
    }

    var metadataDescription: String {
        get { document.metadataDescription }
        set { document.metadataDescription = newValue }
    }

    var distributionURL: String {
        get { document.distributionURL }
        set { document.distributionURL = newValue }
    }

    var version: String {
        get { document.version }
        set { document.version = newValue }
    }

    var appearance: ThemeDocument.Appearance {
        get { document.appearance }
        set { document.appearance = newValue }
    }

    var editor: ThemeDocument.EditorColors {
        get { document.editor }
        set { document.editor = newValue }
    }

    var terminal: ThemeDocument.TerminalColors {
        get { document.terminal }
        set { document.terminal = newValue }
    }

    var interface: ThemeDocument.InterfaceColors? {
        get { document.interface }
        set { document.interface = newValue }
    }

    var isBundled: Bool {
        source.isBuiltIn
    }

    var isEditable: Bool {
        source.isEditable
    }

    var isExtensionTheme: Bool {
        source.packID != nil
    }
}

extension Theme {
    static var fallback: Theme {
        func attributes(_ color: String) -> Attributes {
            Attributes(color: color)
        }
        let editor = EditorColors(
            text: attributes("#FFFFFF"),
            insertionPoint: attributes("#007AFF"),
            invisibles: attributes("#53606E"),
            background: attributes("#292A30"),
            lineHighlight: attributes("#2F3239"),
            selection: attributes("#646F83"),
            keywords: attributes("#FF7AB2"),
            commands: attributes("#78C2B3"),
            types: attributes("#6BDFFF"),
            attributes: attributes("#CC9768"),
            variables: attributes("#4EB0CC"),
            values: attributes("#B281EB"),
            numbers: attributes("#D9C97C"),
            strings: attributes("#FF8170"),
            characters: attributes("#D9C97C"),
            comments: attributes("#7F8C98")
        )
        let terminal = TerminalColors(
            text: attributes("#FFFFFF"),
            boldText: attributes("#D9D9D9"),
            cursor: attributes("#FFFFFF"),
            background: attributes("#292A30"),
            selection: attributes("#646F83"),
            black: attributes("#1F2024"),
            red: attributes("#FF8170"),
            green: attributes("#78C2B3"),
            yellow: attributes("#D9C97C"),
            blue: attributes("#B281EB"),
            magenta: attributes("#FF7AB2"),
            cyan: attributes("#4EB0CC"),
            white: attributes("#D9D9D9"),
            brightBlack: attributes("#8E8E93"),
            brightRed: attributes("#FF8170"),
            brightGreen: attributes("#78C2B3"),
            brightYellow: attributes("#D9C97C"),
            brightBlue: attributes("#B281EB"),
            brightMagenta: attributes("#FF7AB2"),
            brightCyan: attributes("#4EB0CC"),
            brightWhite: attributes("#FFFFFF")
        )
        return Theme(
            id: "fallback",
            source: .bundled,
            fileURL: nil,
            document: ThemeDocument(
                name: "fallback",
                displayName: "Fallback",
                appearance: .dark,
                editor: editor,
                terminal: terminal
            )
        )
    }

    typealias ThemeType = ThemeDocument.Appearance
    typealias Attributes = ThemeDocument.Attributes
    typealias EditorColors = ThemeDocument.EditorColors
    typealias TerminalColors = ThemeDocument.TerminalColors
    typealias InterfaceColors = ThemeDocument.InterfaceColors
}
