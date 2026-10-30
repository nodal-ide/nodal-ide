import SwiftUI
import CodeEditLang

struct ThemePalette: Equatable {
    let themeID: String
    let appearance: ThemeDocument.Appearance
    let materials: ThemeDocument.MaterialMode

    let accent: Color
    let windowBackground: Color
    let sidebarBackground: Color
    let toolbarBackground: Color
    let tabBarBackground: Color
    let tabActiveBackground: Color
    let tabInactiveBackground: Color
    let panelBackground: Color
    let overlayBackground: Color
    let separator: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let disabledText: Color
    let controlBackground: Color
    let controlBorder: Color
    let focusRing: Color
    let selectionBackground: Color
    let selectionForeground: Color
    let link: Color
    let success: Color
    let warning: Color
    let error: Color
    let info: Color

    var colorScheme: ColorScheme {
        appearance == .dark ? .dark : .light
    }

    var isSolid: Bool {
        materials == .solid
    }

    func color(for surface: ThemeSurface) -> Color {
        switch surface {
        case .window:
            return windowBackground
        case .sidebar:
            return sidebarBackground
        case .toolbar:
            return toolbarBackground
        case .tabBar:
            return tabBarBackground
        case .tabActive:
            return tabActiveBackground
        case .tabInactive:
            return tabInactiveBackground
        case .panel:
            return panelBackground
        case .overlay:
            return overlayBackground
        case .control:
            return controlBackground
        }
    }
}

extension ThemePalette {
    static let standard = ThemeResolver.resolve(Theme.fallback)
}
