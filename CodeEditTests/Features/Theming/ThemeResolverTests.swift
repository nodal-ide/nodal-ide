import Foundation
import SwiftUI
import Testing
import CodeEditLang
@testable import CodeEdit

@Suite
struct ThemeResolverTests {
    private func document(
        name: String = "test",
        appearance: ThemeDocument.Appearance = .dark,
        background: String = "#101418",
        text: String = "#E6E9F2",
        insertionPoint: String = "#4C8DFF",
        interface: ThemeDocument.InterfaceColors? = nil
    ) -> ThemeDocument {
        return ThemeDocument(
            name: name,
            displayName: name,
            appearance: appearance,
            editor: editorColors(text: text, background: background, insertionPoint: insertionPoint),
            terminal: terminalColors(text: text, background: background),
            interface: interface
        )
    }

    private func editorColors(text: String, background: String, insertionPoint: String) -> ThemeDocument.EditorColors {
        func attributes(_ color: String) -> ThemeDocument.Attributes {
            .init(color: color)
        }
        return ThemeDocument.EditorColors(
            text: attributes(text),
            insertionPoint: attributes(insertionPoint),
            invisibles: attributes("#53606E"),
            background: attributes(background),
            lineHighlight: attributes("#151A20"),
            selection: attributes("#2A4A7F"),
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
    }

    private func terminalColors(text: String, background: String) -> ThemeDocument.TerminalColors {
        func attributes(_ color: String) -> ThemeDocument.Attributes {
            .init(color: color)
        }
        return ThemeDocument.TerminalColors(
            text: attributes(text),
            boldText: attributes(text),
            cursor: attributes(text),
            background: attributes(background),
            selection: attributes("#2A4A7F"),
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
    }

    @Test
    func resolutionIsDeterministic() {
        let theme = document()
        let first = ThemeResolver.resolve(theme, themeID: "user:test")
        let second = ThemeResolver.resolve(theme, themeID: "user:test")

        #expect(first == second)
        #expect(first.themeID == "user:test")
        #expect(first.appearance == .dark)
        #expect(first.materials == .system)
    }

    @Test
    func explicitTokensWinOverDerivation() {
        let interface = ThemeDocument.InterfaceColors(
            accent: "#FF0000",
            windowBackground: "#010203",
            separator: "#0A0B0C",
            materials: .solid
        )
        let palette = ThemeResolver.resolve(document(interface: interface), themeID: "user:test")

        #expect(palette.accent == Color(hex: "#FF0000"))
        #expect(palette.windowBackground == Color(hex: "#010203"))
        #expect(palette.separator == Color(hex: "#0A0B0C"))
        #expect(palette.materials == .solid)
        #expect(palette.isSolid)
    }

    @Test
    func missingInterfaceTokensAreDerivedForLightAndDarkThemes() {
        for appearance in ThemeDocument.Appearance.allCases {
            let palette = ThemeResolver.resolve(
                document(
                    appearance: appearance,
                    background: appearance == .dark ? "#101418" : "#FAFAFA",
                    text: appearance == .dark ? "#E6E9F2" : "#1C1C1E"
                )
            )
            #expect(palette.appearance == appearance)
            #expect(palette.windowBackground != palette.sidebarBackground)
            #expect(palette.textPrimary != palette.textSecondary)
            #expect(palette.selectionForeground == Color(hex: "#E6E9F2")
                || palette.selectionForeground == Color.white
                || palette.selectionForeground == Color.black
                || palette.selectionForeground == Color(hex: "#1C1C1E"))
        }
    }

    @Test
    func fallbackPaletteIsAvailableWithoutCatalog() {
        let palette = ThemePalette.standard

        #expect(palette.appearance == .dark)
        #expect(palette.accent == Color(hex: Theme.fallback.document.editor.insertionPoint.color))
        #expect(palette.colorScheme == .dark)
    }

    @Test
    func colorParsingRejectsInvalidHex() {
        #expect(ThemeRGB(hex: "#123") != nil)
        #expect(ThemeRGB(hex: "#112233") != nil)
        #expect(ThemeRGB(hex: "#11223344") != nil)
        #expect(ThemeRGB(hex: "#12") == nil)
        #expect(ThemeRGB(hex: "#GGGGGG") == nil)
        #expect(ThemeRGB(hex: "rgb(0,0,0)") == nil)
    }

    @Test
    func selectionForegroundKeepsReadableContrast() {
        let palette = ThemeResolver.resolve(document())
        let background = ThemeRGB(hex: palette.selectionBackground.hexString)
        let foreground = ThemeRGB(hex: palette.selectionForeground.hexString)

        #expect(background != nil)
        #expect(foreground != nil)
        if let background, let foreground {
            #expect(foreground.contrastRatio(with: background) >= 4.5)
        }
    }
}
