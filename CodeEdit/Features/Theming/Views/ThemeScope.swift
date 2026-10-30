import SwiftUI

private struct ThemePaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemePalette.standard
}

extension EnvironmentValues {
    var theme: ThemePalette {
        get { self[ThemePaletteEnvironmentKey.self] }
        set { self[ThemePaletteEnvironmentKey.self] = newValue }
    }
}

struct ThemeScope: ViewModifier {
    @ObservedObject private var themeModel: ThemeModel = AppServices.themeModel

    func body(content: Content) -> some View {
        content
            .environment(\.theme, themeModel.palette)
            .environment(\.colorScheme, themeModel.palette.colorScheme)
            .tint(themeModel.palette.accent)
    }
}

extension View {
    func themeScope() -> some View {
        modifier(ThemeScope())
    }
}
