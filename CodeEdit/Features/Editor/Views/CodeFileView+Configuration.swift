//
//  CodeFileView+Configuration.swift
//  CodeEdit
//
//  Builds the `SourceEditorConfiguration` (appearance/behavior/layout/peripherals) from the current
//  settings and theme, keeping the view body free of configuration wiring.
//

import AppKit
import SwiftUI
import CodeEditSourceEditor

extension CodeFileView {
    /// The editor configuration derived from the current settings and theme.
    var editorConfiguration: SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: currentTheme.editor.editorTheme,
                useThemeBackground: useThemeBackground,
                font: font,
                lineHeightMultiple: lineHeightMultiple,
                letterSpacing: letterSpacing,
                wrapLines: wrapLinesToEditorWidth,
                useSystemCursor: useSystemCursor,
                tabWidth: defaultTabWidth,
                bracketPairEmphasis: bracketPairEmphasisStyle
            ),
            behavior: .init(
                isEditable: isEditable,
                indentOption: indentOption.textViewOption(),
                reformatAtColumn: reformatAtColumn
            ),
            layout: .init(
                editorOverscroll: overscroll.overscrollPercentage,
                contentInsets: edgeInsets.nsEdgeInsets,
                additionalTextInsets: NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
            ),
            peripherals: .init(
                showGutter: showGutter,
                showMinimap: isPreview ? false : (showMinimap && isSmallDocument),
                showReformattingGuide: showReformattingGuide,
                showFoldingRibbon: showFoldingRibbon,
                invisibleCharactersConfiguration: invisibleCharactersConfiguration.textViewOption(),
                warningCharacters: Set(warningCharacters.characters.keys)
            )
        )
    }

    var currentTheme: Theme {
        themeModel.selectedTheme ?? themeModel.themes.first!
    }

    /// The bracket-pair emphasis style derived from the setting and current theme.
    var bracketPairEmphasisStyle: BracketPairEmphasis? {
        let color = if Settings[\.textEditing].bracketEmphasis.useCustomColor {
            Settings[\.textEditing].bracketEmphasis.color.nsColor
        } else {
            currentTheme.editor.text.nsColor.withAlphaComponent(0.8)
        }

        switch Settings[\.textEditing].bracketEmphasis.highlightType {
        case .disabled:
            return nil
        case .flash:
            return .flash
        case .bordered:
            return .bordered(color: color)
        case .underline:
            return .underline(color: color)
        }
    }
}
