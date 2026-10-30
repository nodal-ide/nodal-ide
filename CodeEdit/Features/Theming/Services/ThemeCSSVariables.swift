import SwiftUI

enum ThemeCSSVariables {
    static func css(for palette: ThemePalette) -> String {
        let scheme = palette.appearance == .dark ? "dark" : "light"
        return """
        :root {
            color-scheme: \(scheme);
            --theme-bg: \(palette.windowBackground.hexString);
            --theme-surface: \(palette.panelBackground.hexString);
            --theme-text: \(palette.textPrimary.hexString);
            --theme-secondary: \(palette.textSecondary.hexString);
            --theme-tertiary: \(palette.textTertiary.hexString);
            --theme-border: \(palette.separator.hexString);
            --theme-accent: \(palette.accent.hexString);
            --theme-selection: \(palette.selectionBackground.hexString);
        }
        """
    }
}
