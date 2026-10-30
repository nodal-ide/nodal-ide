import Foundation
import CodeEditLang

enum ThemeResolver {
    static func resolve(_ theme: Theme) -> ThemePalette {
        resolve(theme.document, themeID: theme.id)
    }

    static func resolve(_ document: ThemeDocument, themeID: String = "fallback") -> ThemePalette {
        let base = ThemeRGB(hex: document.editor.background.color)
            ?? ThemeRGB(red: 0.16, green: 0.16, blue: 0.19)
        let text = ThemeRGB(hex: document.editor.text.color)
            ?? ThemeRGB(red: 1, green: 1, blue: 1)
        let accent = ThemeRGB(hex: document.editor.insertionPoint.color)
            ?? ThemeRGB(red: 0, green: 0.48, blue: 1)
        let chrome = ResolvedChrome(base: base, text: text, accent: accent, interface: document.interface)
        let textColors = ResolvedText(
            text: text,
            windowBackground: chrome.windowBackground,
            selectionBackground: chrome.selectionBackground,
            accent: chrome.accent,
            interface: document.interface
        )
        let status = ResolvedStatus(dark: document.appearance == .dark, interface: document.interface)

        return ThemePalette(
            themeID: themeID,
            appearance: document.appearance,
            materials: document.interface?.materials ?? .system,
            accent: chrome.accent.color,
            windowBackground: chrome.windowBackground.color,
            sidebarBackground: chrome.sidebarBackground.color,
            toolbarBackground: chrome.toolbarBackground.color,
            tabBarBackground: chrome.tabBarBackground.color,
            tabActiveBackground: chrome.tabActiveBackground.color,
            tabInactiveBackground: chrome.tabInactiveBackground.color,
            panelBackground: chrome.panelBackground.color,
            overlayBackground: chrome.overlayBackground.color,
            separator: chrome.separator.color,
            textPrimary: textColors.primary.color,
            textSecondary: textColors.secondary.color,
            textTertiary: textColors.tertiary.color,
            disabledText: textColors.disabled.color,
            controlBackground: chrome.controlBackground.color,
            controlBorder: chrome.controlBorder.color,
            focusRing: chrome.accent.color,
            selectionBackground: chrome.selectionBackground.color,
            selectionForeground: textColors.selectionForeground.color,
            link: textColors.link.color,
            success: status.success.color,
            warning: status.warning.color,
            error: status.error.color,
            info: status.info.color
        )
    }
}

private func resolved(_ token: String?, fallback: ThemeRGB) -> ThemeRGB {
    guard let token, let parsed = ThemeRGB(hex: token) else { return fallback }
    return parsed
}

private struct ResolvedChrome {
    let windowBackground: ThemeRGB
    let sidebarBackground: ThemeRGB
    let toolbarBackground: ThemeRGB
    let tabBarBackground: ThemeRGB
    let tabActiveBackground: ThemeRGB
    let tabInactiveBackground: ThemeRGB
    let panelBackground: ThemeRGB
    let overlayBackground: ThemeRGB
    let separator: ThemeRGB
    let controlBackground: ThemeRGB
    let controlBorder: ThemeRGB
    let accent: ThemeRGB
    let selectionBackground: ThemeRGB

    init(base: ThemeRGB, text: ThemeRGB, accent: ThemeRGB, interface: ThemeDocument.InterfaceColors?) {
        windowBackground = resolved(interface?.windowBackground, fallback: base)
        sidebarBackground = resolved(interface?.sidebarBackground, fallback: base.mixed(with: text, amount: 0.03))
        toolbarBackground = resolved(interface?.toolbarBackground, fallback: base.mixed(with: text, amount: 0.05))
        tabBarBackground = resolved(interface?.tabBarBackground, fallback: base.mixed(with: text, amount: 0.03))
        tabInactiveBackground = resolved(
            interface?.tabInactiveBackground,
            fallback: base.mixed(with: text, amount: 0.03)
        )
        tabActiveBackground = resolved(interface?.tabActiveBackground, fallback: base.mixed(with: text, amount: 0.07))
        panelBackground = resolved(interface?.panelBackground, fallback: base.mixed(with: text, amount: 0.05))
        overlayBackground = resolved(interface?.overlayBackground, fallback: base.mixed(with: text, amount: 0.08))
        separator = resolved(interface?.separator, fallback: base.mixed(with: text, amount: 0.18))
        controlBackground = resolved(interface?.controlBackground, fallback: base.mixed(with: text, amount: 0.06))
        controlBorder = resolved(interface?.controlBorder, fallback: base.mixed(with: text, amount: 0.2))
        self.accent = resolved(interface?.accent, fallback: accent)
        selectionBackground = resolved(
            interface?.selectionBackground,
            fallback: windowBackground.mixed(with: self.accent, amount: 0.32)
        )
    }
}

private struct ResolvedText {
    let primary: ThemeRGB
    let secondary: ThemeRGB
    let tertiary: ThemeRGB
    let disabled: ThemeRGB
    let selectionForeground: ThemeRGB
    let link: ThemeRGB

    init(
        text: ThemeRGB,
        windowBackground: ThemeRGB,
        selectionBackground: ThemeRGB,
        accent: ThemeRGB,
        interface: ThemeDocument.InterfaceColors?
    ) {
        primary = resolved(interface?.textPrimary, fallback: text)
        secondary = resolved(interface?.textSecondary, fallback: text.mixed(with: windowBackground, amount: 0.32))
        tertiary = resolved(interface?.textTertiary, fallback: text.mixed(with: windowBackground, amount: 0.54))
        disabled = resolved(interface?.disabledText, fallback: text.mixed(with: windowBackground, amount: 0.68))
        let contrasting = selectionBackground.isLight
            ? ThemeRGB(red: 0, green: 0, blue: 0)
            : ThemeRGB(red: 1, green: 1, blue: 1)
        selectionForeground = resolved(
            interface?.selectionForeground,
            fallback: primary.contrastRatio(with: selectionBackground) >= 4.5
                ? primary
                : contrasting
        )
        link = resolved(
            interface?.link,
            fallback: accent.ensuringContrast(against: windowBackground, target: primary)
        )
    }
}

private struct ResolvedStatus {
    let success: ThemeRGB
    let warning: ThemeRGB
    let error: ThemeRGB
    let info: ThemeRGB

    init(dark: Bool, interface: ThemeDocument.InterfaceColors?) {
        success = resolved(interface?.success, fallback: Self.semantic(.success, dark: dark))
        warning = resolved(interface?.warning, fallback: Self.semantic(.warning, dark: dark))
        error = resolved(interface?.error, fallback: Self.semantic(.error, dark: dark))
        info = resolved(interface?.info, fallback: Self.semantic(.info, dark: dark))
    }

    private enum Role {
        case success
        case warning
        case error
        case info
    }

    private static func semantic(_ role: Role, dark: Bool) -> ThemeRGB {
        switch (role, dark) {
        case (.success, true):
            return ThemeRGB(red: 0.19, green: 0.82, blue: 0.35)
        case (.success, false):
            return ThemeRGB(red: 0.14, green: 0.54, blue: 0.24)
        case (.warning, true):
            return ThemeRGB(red: 1, green: 0.84, blue: 0.04)
        case (.warning, false):
            return ThemeRGB(red: 0.7, green: 0.42, blue: 0)
        case (.error, true):
            return ThemeRGB(red: 1, green: 0.27, blue: 0.23)
        case (.error, false):
            return ThemeRGB(red: 0.84, green: 0, blue: 0.08)
        case (.info, true):
            return ThemeRGB(red: 0.39, green: 0.82, blue: 1)
        case (.info, false):
            return ThemeRGB(red: 0, green: 0.44, blue: 0.89)
        }
    }
}
