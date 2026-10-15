//
//  UtilityAreaTerminal.swift
//  CodeEdit
//
//  Created by Austin Condiff on 5/25/23.
//

import SwiftUI
import Cocoa

struct UtilityAreaTerminalView: View {
    @AppSettings(\.theme.matchAppearance)
    private var matchAppearance
    @AppSettings(\.terminal.darkAppearance)
    private var darkAppearance
    @AppSettings(\.theme.useThemeBackground)
    private var useThemeBackground
    @AppSettings(\.textEditing.font)
    private var textEditingFont
    @AppSettings(\.terminal.font)
    private var terminalFont
    @AppSettings(\.terminal.useTextEditorFont)
    private var useTextEditorFont

    @Environment(\.colorScheme)
    private var colorScheme

    @EnvironmentObject private var workspace: WorkspaceDocument

    @EnvironmentObject private var utilityAreaViewModel: UtilityAreaViewModel

    @State private var sidebarIsCollapsed = false

    @StateObject private var themeModel: ThemeModel = .shared

    @State private var isMenuVisible = false

    @State private var popoverSource: CGRect = .zero

    var font: NSFont {
        useTextEditorFont == true ? textEditingFont.current : terminalFont.current
    }

    /// Returns the `background` color of the selected theme
    private var backgroundColor: NSColor {
        if let selectedTheme = matchAppearance && darkAppearance
            ? themeModel.selectedDarkTheme
            : themeModel.selectedTheme,
           let index = themeModel.themes.firstIndex(of: selectedTheme) {
            return NSColor(themeModel.themes[index].terminal.background.swiftColor)
        }
        return .windowBackgroundColor
    }

    /// Decides the color scheme used in the terminal.
    ///
    /// Decision list:
    /// - If there is no selection, use the system color scheme ``UtilityAreaTerminalView/colorScheme``
    /// - If the match appearance and dark appearance settings are true, return dark if the selected dark theme is dark.
    /// - Otherwise, return dark if the selected theme is dark.
    private var terminalColorScheme: ColorScheme {
        return if utilityAreaViewModel.selectedTerminals.isEmpty {
            colorScheme
        } else if matchAppearance && darkAppearance {
            themeModel.selectedDarkTheme?.appearance == .dark ? .dark : .light
        } else {
            themeModel.selectedTheme?.appearance == .dark ? .dark : .light
        }
    }

    /// Finds the selected terminal.
    /// - Returns: The selected terminal.
    private func getSelectedTerminal() -> UtilityAreaTerminal? {
        guard let selectedTerminalID = utilityAreaViewModel.selectedTerminals.first else {
            return nil
        }
        return utilityAreaViewModel.terminals.first(where: { $0.id == selectedTerminalID })
    }

    /// Finds the split (secondary) terminal, if any.
    private func getSplitTerminal() -> UtilityAreaTerminal? {
        guard let id = utilityAreaViewModel.splitTerminalID else { return nil }
        return utilityAreaViewModel.terminals.first(where: { $0.id == id })
    }

    private func isFocused(_ terminal: UtilityAreaTerminal) -> Bool {
        let focused = utilityAreaViewModel.focusedTerminalID ?? utilityAreaViewModel.selectedTerminals.first
        return focused == terminal.id
    }

    @ViewBuilder private var terminalContent: some View {
        if utilityAreaViewModel.isSplit,
           let primary = getSelectedTerminal(),
           let secondary = getSplitTerminal(),
           primary.id != secondary.id {
            switch utilityAreaViewModel.splitAxis {
            case .horizontal:
                HSplitView {
                    pane(primary, fill: true)
                    pane(secondary, fill: true)
                }
            case .vertical:
                VSplitView {
                    pane(primary, fill: true)
                    pane(secondary, fill: true)
                }
            }
        } else if let terminal = getSelectedTerminal() {
            pane(terminal, fill: false)
        } else {
            CEContentUnavailableView("No Selection")
        }
    }

    /// Renders a single terminal pane. When `fill` is `false` the terminal is aligned to the bottom of the pane.
    private func pane(_ terminal: UtilityAreaTerminal, fill: Bool) -> some View {
        GeometryReader { geometry in
            let containerHeight = geometry.size.height
            let totalFontHeight = fontTotalHeight(nsFont: font).rounded(.up)
            let constrainedHeight = totalFontHeight > 0
                ? containerHeight - containerHeight.truncatingRemainder(dividingBy: totalFontHeight)
                : containerHeight
            VStack(spacing: 0) {
                if !fill {
                    Spacer(minLength: 0).frame(minHeight: 0)
                }
                TerminalEmulatorView(
                    url: terminal.url,
                    terminalID: terminal.id,
                    shellType: terminal.shell,
                    onTitleChange: { newTitle in
                        // This can be called whenever, even in a view update so it needs to be dispatched.
                        DispatchQueue.main.async { [weak utilityAreaViewModel] in
                            utilityAreaViewModel?.updateTerminal(terminal.id, title: newTitle)
                        }
                    }
                )
                .frame(height: fill ? nil : max(0, constrainedHeight - 1))
                .id(terminal.id)
                .accessibilityIdentifier("terminal")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(
                    utilityAreaViewModel.isSplit && isFocused(terminal) ? Color.accentColor.opacity(0.5) : .clear,
                    lineWidth: 1
                )
        }
        .onHover { hovering in
            if hovering {
                utilityAreaViewModel.focusTerminal(terminal.id)
            }
        }
    }

    /// Estimate the font's height for keeping the terminal aligned with the bottom.
    /// - Parameter nsFont: The font being used in the terminal.
    /// - Returns: The height in pixels of the font.
    func fontTotalHeight(nsFont: NSFont) -> CGFloat {
        let ctFont = nsFont as CTFont
        let ascent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)
        return ascent + descent + leading
    }

    var body: some View {
        UtilityAreaTabView(model: utilityAreaViewModel.tabViewModel) { tabState in
            ZStack {
                // Keeps the sidebar from changing sizes because TerminalEmulatorView takes a µs to load in
                HStack { Spacer() }

                terminalContent
            }
            .padding(.horizontal, 10)
            .paneToolbar {
                PaneToolbarSection {
                    UtilityAreaTerminalPicker(
                        selectedIDs: Binding(
                            get: { utilityAreaViewModel.selectedTerminals },
                            set: { utilityAreaViewModel.setSelectedTerminals($0) }
                        ),
                        terminals: utilityAreaViewModel.terminals
                    )
                    .opacity(tabState.leadingSidebarIsCollapsed ? 1 : 0)
                }
                Spacer()
                PaneToolbarSection {
                    Button {
                        guard let terminal = getSelectedTerminal() else {
                            return
                        }
                        utilityAreaViewModel.replaceTerminal(terminal.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Reset the terminal")
                    .disabled(getSelectedTerminal() == nil)
                    Menu {
                        Button("Split Right") {
                            utilityAreaViewModel.splitFocusedTerminal(axis: .horizontal)
                        }
                        .disabled(utilityAreaViewModel.isSplit)
                        Button("Split Down") {
                            utilityAreaViewModel.splitFocusedTerminal(axis: .vertical)
                        }
                        .disabled(utilityAreaViewModel.isSplit)
                        if utilityAreaViewModel.isSplit {
                            Divider()
                            Button("Close Split") {
                                utilityAreaViewModel.closeSplit()
                            }
                        }
                    } label: {
                        Image(systemName: "square.split.2x1")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(getSelectedTerminal() == nil)
                    .help("Split the terminal")
                }
            }
            .background {
                backgroundEffectView
            }
            .colorScheme(terminalColorScheme)
        } leadingSidebar: { _ in
            UtilityAreaTerminalSidebar()
        }
        .onAppear {
            guard let workspaceURL = workspace.fileURL else {
                assertionFailure("Workspace does not have a file URL.")
                return
            }
            utilityAreaViewModel.initializeTerminals(workspaceURL: workspaceURL)
        }
        .accessibilityIdentifier("terminal-area")
    }

    @ViewBuilder var backgroundEffectView: some View {
        if utilityAreaViewModel.selectedTerminals.isEmpty {
            EffectView(.contentBackground)
        } else if useThemeBackground {
            Color(nsColor: backgroundColor)
        } else {
            if colorScheme == .dark {
                EffectView(.underPageBackground)
            } else {
                EffectView(.contentBackground)
            }
        }
    }
}
