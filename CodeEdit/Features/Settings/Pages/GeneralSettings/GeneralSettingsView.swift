//
//  GeneralSettingsView.swift
//  CodeEdit
//
//  Created by Austin Condiff on 4/1/23.
//

import SwiftUI

/// A view that implements the `General` settings page
struct GeneralSettingsView: View {
    private let inputWidth: Double = 160
    private let textEditorWidth: Double = 220
    private let textEditorHeight: Double = 30

    @EnvironmentObject var updater: SoftwareUpdater
    @FocusState private var focusedField: UUID?

    @AppSettings(\.general)
    var settings

    @State private var openInCodeEdit: Bool = true
    @State private var shellCommandInstalled = false
    @State private var installingShellCommand = false
    @State private var shellCommandError: String?

    init() {
        self.openInCodeEdit = UserDefaults.appGroup.bool(forKey: "enableOpenInCE")
    }

    var body: some View {
        SettingsForm {
            Section {
                appearance
                fileIconStyle
                showEditorJumpBar
                dimEditorsWithoutFocus
                navigatorTabBarPosition
                inspectorTabBarPosition
            }
            Section {
                showIssues
                showLiveIssues
            }
            Section {
                autoSave
                revealFileOnFocusChangeToggle
                reopenBehavior
                afterWindowsCloseBehaviour
                fileExtensions
            }
            Section {
                projectNavigatorSize
                maximumOpenTabs
                findNavigatorDetail
                issueNavigatorDetail
            }
            Section {
                openInCodeEditToggle
                shellCommand
                dialogWarnings

            }
            Section {
                updateChecker
                autoUpdateToggle
                // TODO: Uncomment when production build is released.
                // prereleaseToggle
            }
        }
        .onAppear {
            shellCommandInstalled = ShellCommandInstaller.isInstalled()
        }
        .alert(
            "Could Not Install Shell Command",
            isPresented: Binding(
                get: { shellCommandError != nil },
                set: { if !$0 { shellCommandError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                shellCommandError = nil
            }
        } message: {
            Text(shellCommandError ?? "")
        }
    }
}

/// The extension of the view with all the preferences
private extension GeneralSettingsView {
    var appearance: some View {
        Picker("Appearance", selection: $settings.appAppearance) {
            Text("System")
                .tag(SettingsData.Appearances.system)
            Divider()
            Text("Light")
                .tag(SettingsData.Appearances.light)
            Text("Dark")
                .tag(SettingsData.Appearances.dark)
        }
        .onChange(of: settings.appAppearance) { _, tag in
            tag.applyAppearance()
        }
    }

    // TODO: Implement reflecting Show Issues preference and remove disabled modifier
    var showIssues: some View {
        Picker("Show Issues", selection: $settings.showIssues) {
            Text("Show Inline")
                .tag(SettingsData.Issues.inline)
            Text("Show Minimized")
                .tag(SettingsData.Issues.minimized)
        }
    }

    var showLiveIssues: some View {
        Toggle("Show Live Issues", isOn: $settings.showLiveIssues)
    }

    var showEditorJumpBar: some View {
        Toggle("Show Jump Bar", isOn: $settings.showEditorJumpBar)
    }

    var dimEditorsWithoutFocus: some View {
        Toggle("Dim editors without focus", isOn: $settings.dimEditorsWithoutFocus)
    }

    var fileExtensions: some View {
        Group {
            Picker("File Extensions", selection: $settings.fileExtensionsVisibility) {
                Text("Hide all")
                    .tag(SettingsData.FileExtensionsVisibility.hideAll)
                Text("Show all")
                    .tag(SettingsData.FileExtensionsVisibility.showAll)
                Divider()
                Text("Show only")
                    .tag(SettingsData.FileExtensionsVisibility.showOnly)
                Text("Hide only")
                    .tag(SettingsData.FileExtensionsVisibility.hideOnly)
            }
            if case .showOnly = settings.fileExtensionsVisibility {
                TextField("", text: $settings.shownFileExtensions.string, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...3)
            }
            if case .hideOnly = settings.fileExtensionsVisibility {
                TextField("", text: $settings.hiddenFileExtensions.string, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...3)
            }
        }
    }

    var fileIconStyle: some View {
        Picker("File Icon Style", selection: $settings.fileIconStyle) {
            Text("Color")
                .tag(SettingsData.FileIconStyle.color)
            Text("Monochrome")
                .tag(SettingsData.FileIconStyle.monochrome)
        }
        .pickerStyle(.radioGroup)
    }

    var navigatorTabBarPosition: some View {
        Picker("Navigator Tab Bar Position", selection: $settings.navigatorTabBarPosition) {
            Text("Top")
                .tag(SettingsData.SidebarTabBarPosition.top)
            Text("Side")
                .tag(SettingsData.SidebarTabBarPosition.side)
        }
        .pickerStyle(.radioGroup)
    }

    var inspectorTabBarPosition: some View {
        Picker("Inspector Tab Bar Position", selection: $settings.inspectorTabBarPosition) {
            Text("Top")
                .tag(SettingsData.SidebarTabBarPosition.top)
            Text("Side")
                .tag(SettingsData.SidebarTabBarPosition.side)
        }
        .pickerStyle(.radioGroup)
    }

    var reopenBehavior: some View {
        Picker("Reopen Behavior", selection: $settings.reopenBehavior) {
            Text("Welcome Screen")
                .tag(SettingsData.ReopenBehavior.welcome)
            Divider()
            Text("Open Panel")
                .tag(SettingsData.ReopenBehavior.openPanel)
            Text("New Document")
                .tag(SettingsData.ReopenBehavior.newDocument)
        }
    }

    var afterWindowsCloseBehaviour: some View {
        Picker(
            "After the last window is closed",
            selection: $settings.reopenWindowAfterClose
        ) {
            Text("Do nothing")
                .tag(SettingsData.ReopenWindowBehavior.doNothing)
            Divider()
            Text("Show Welcome Window")
                .tag(SettingsData.ReopenWindowBehavior.showWelcomeWindow)
            Text("Quit")
                .tag(SettingsData.ReopenWindowBehavior.quit)
        }
    }

    var projectNavigatorSize: some View {
        Picker("Project Navigator Size", selection: $settings.projectNavigatorSize) {
            Text("Small")
                .tag(SettingsData.ProjectNavigatorSize.small)
            Text("Medium")
                .tag(SettingsData.ProjectNavigatorSize.medium)
            Text("Large")
                .tag(SettingsData.ProjectNavigatorSize.large)
        }
    }

    var maximumOpenTabs: some View {
        Stepper(
            "Maximum Open Tabs: \(settings.effectiveMaximumOpenTabs)",
            value: $settings.maximumOpenTabs,
            in: 5...200
        )
    }

    var findNavigatorDetail: some View {
        Picker("Find Navigator Detail", selection: $settings.findNavigatorDetail) {
            ForEach(SettingsData.NavigatorDetail.allCases, id: \.self) { tag in
                Text(tag.label).tag(tag)
            }
        }
    }

    // TODO: Implement reflecting Issue Navigator Detail preference and remove disabled modifier
    var issueNavigatorDetail: some View {
        Picker("Issue Navigator Detail", selection: $settings.issueNavigatorDetail) {
            ForEach(SettingsData.NavigatorDetail.allCases, id: \.self) { tag in
                Text(tag.label).tag(tag)
            }
        }
        .disabled(true)
    }

    // TODO: Implement reset for Don't Ask Me warnings Button and remove disabled modifier
    var dialogWarnings: some View {
        LabeledContent("Dialog Warnings") {
            Button(action: {
            }, label: {
                Text("Reset \"Don't Ask Me\" Warnings")
            })
            .buttonStyle(.bordered)
        }
        .disabled(true)
    }

    var shellCommand: some View {
        LabeledContent("'codeedit' Shell Command") {
            HStack(spacing: 8) {
                if shellCommandInstalled {
                    Text("Installed")
                        .foregroundStyle(.secondary)
                }
                if installingShellCommand {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(shellCommandInstalled ? "Reinstall" : "Install") {
                    installShellCommand()
                }
                .disabled(installingShellCommand)
                .buttonStyle(.bordered)
            }
        }
    }

    @MainActor
    private func installShellCommand() {
        installingShellCommand = true
        Task {
            let result = await ShellCommandInstaller.install()
            installingShellCommand = false
            switch result {
            case .success:
                shellCommandInstalled = true
            case .failure(let error):
                shellCommandError = error.localizedDescription
            }
        }
    }

    var updateChecker: some View {
        Section {
            LabeledContent {
                Button("Check Now") {
                    updater.checkForUpdates()
                }
            } label: {
                Text("Check for updates")
                Text("Last checked: \(lastUpdatedString)")

            }
        }
    }

    var autoUpdateToggle: some View {
        Toggle("Automatically check for app updates", isOn: $updater.automaticallyChecksForUpdates)
    }

    var prereleaseToggle: some View {
        Toggle("Include pre-release versions", isOn: $updater.includePrereleaseVersions)
    }

    var autoSave: some View {
        Toggle("Automatically save changes to disk", isOn: $settings.isAutoSaveOn)
    }

    // MARK: - Preference Views

    private var lastUpdatedString: String {
        if let lastUpdatedDate = updater.lastUpdateCheckDate {
            return Self.formatter.string(from: lastUpdatedDate)
        } else {
            return "Never"
        }
    }

    private static func configure<Subject>(_ subject: Subject, configuration: (inout Subject) -> Void) -> Subject {
        var copy = subject
        configuration(&copy)
        return copy
    }

    var openInCodeEditToggle: some View {
        Toggle("Show “Open in Nodal IDE” option in Finder", isOn: $openInCodeEdit)
            .onChange(of: openInCodeEdit) { _, newValue in
                UserDefaults.appGroup.set(newValue, forKey: "enableOpenInCE")
            }
    }

    var revealFileOnFocusChangeToggle: some View {
        Toggle("Automatically reveal in project navigator", isOn: $settings.revealFileOnFocusChange)
    }

    private static let formatter = configure(DateFormatter()) {
        $0.dateStyle = .medium
        $0.timeStyle = .medium
    }
}
