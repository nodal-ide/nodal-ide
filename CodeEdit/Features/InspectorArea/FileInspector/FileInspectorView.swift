//
//  FileInspectorView.swift
//  CodeEdit
//
//  Created by Nanashi Li on 2022/03/24.
//
import SwiftUI
import CodeEditLanguages

struct FileInspectorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    @EnvironmentObject private var editorManager: EditorManager

    @AppSettings(\.textEditing)
    private var textEditing

    @State private var file: CEWorkspaceFile?

    @State private var fileName: String = ""

    // File settings overrides

    @State private var language: CodeLanguage?

    @State var indentOption: SettingsData.TextEditingSettings.IndentOption = .init(indentType: .tab)

    @State var defaultTabWidth: Int = 0

    @State var wrapLines: Bool = false

    func updateFileOptions(_ textEditingOverride: SettingsData.TextEditingSettings? = nil) {
        let textEditingSettings = textEditingOverride ?? textEditing
        indentOption = file?.fileDocument?.indentOption ?? textEditingSettings.indentOption
        defaultTabWidth = file?.fileDocument?.defaultTabWidth ?? textEditingSettings.defaultTabWidth
        wrapLines = file?.fileDocument?.wrapLines ?? textEditingSettings.wrapLinesToEditorWidth
    }

    func updateInspectorSource() {
        file = editorManager.activeEditor.selectedTab?.file
        fileName = file?.name ?? ""
        language = file?.fileDocument?.language
        updateFileOptions()
    }

    var body: some View {
        Group {
            if file != nil {
                Form {
                    Section("Identity and Type") {
                        fileNameField
                        fileType
                    }
                    Section {
                        location
                    }
                    Section("Text Settings") {
                        indentUsing
                        widthOptions
                        wrapLinesToggle
                    }
                }
            } else {
                NoSelectionInspectorView()
            }
        }
        .onAppear {
            updateInspectorSource()
        }
        .onReceive(editorManager.activeEditor.objectWillChange) { _ in
            updateInspectorSource()
        }
        .onChange(of: editorManager.activeEditor) { _, _ in
            updateInspectorSource()
        }
        .onChange(of: editorManager.activeEditor.selectedTab) { _, _ in
            updateInspectorSource()
        }
        .onChange(of: textEditing) { _, newValue in
            updateFileOptions(newValue)
        }
    }

    @ViewBuilder private var fileNameField: some View {
        if let file {
            TextField("Name", text: $fileName)
                .background(
                    fileName != file.fileName() && !file.validateFileName(for: fileName) ? Color(errorRed) : Color.clear
                )
                .onSubmit {
                    if file.validateFileName(for: fileName) {
                        let destinationURL = file.url
                            .deletingLastPathComponent()
                            .appending(path: fileName)
                        DispatchQueue.main.async { [weak workspace] in
                            do {
                                if let newItem = try workspace?.workspaceFileManager?.move(
                                    file: file,
                                    to: destinationURL
                                ),
                                   !newItem.isFolder {
                                    editorManager.editorLayout.closeAllTabs(of: file)
                                    editorManager.openTab(item: newItem)
                                }
                            } catch {
                                let alert = NSAlert(error: error)
                                alert.addButton(withTitle: "Dismiss")
                                alert.runModal()
                            }
                        }
                    } else {
                        fileName = file.labelFileName()
                    }
                }
        }
    }

    @ViewBuilder private var fileType: some View {
        Group {
            if let catalogStore = workspace.languageCatalogStore {
                ObservedLanguageSelector(store: catalogStore, selection: $language)
            } else {
                LanguageSelector(
                    builtInLanguages: LanguageCatalog.builtIn.languages,
                    contributedLanguages: [],
                    selection: $language
                )
            }
        }
        .onChange(of: language) { _, newValue in
            file?.fileDocument?.language = newValue
        }
    }

    private var location: some View {
        Group {
            if let file {
                LabeledContent("Location") {
                    Button("Choose...") {
                        guard let newURL = chooseNewFileLocation() else {
                            return
                        }
                        // This is ugly but if the tab is opened at the same time as closing the others, it doesn't open
                        // And if the files are re-built at the same time as the tab is opened, it causes a memory error
                        DispatchQueue.main.async { [weak workspace] in
                            do {
                                guard let newItem = try workspace?.workspaceFileManager?.move(file: file, to: newURL),
                                      !newItem.isFolder else {
                                    return
                                }
                                editorManager.editorLayout.closeAllTabs(of: file)
                                editorManager.openTab(item: newItem)
                            } catch {
                                let alert = NSAlert(error: error)
                                alert.addButton(withTitle: "Dismiss")
                                alert.runModal()
                            }
                        }
                    }
                }
                ExternalLink(showInFinder: true, destination: file.url) {
                    Text(file.url.path(percentEncoded: false))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var indentUsing: some View {
        Picker("Indent using", selection: $indentOption.indentType) {
            Text("Spaces").tag(SettingsData.TextEditingSettings.IndentOption.IndentType.spaces)
            Text("Tabs").tag(SettingsData.TextEditingSettings.IndentOption.IndentType.tab)
        }
        .onChange(of: indentOption) { _, newValue in
            file?.fileDocument?.indentOption = newValue == textEditing.indentOption ? nil : newValue
        }
    }

    private var widthOptions: some View {
        LabeledContent("Widths") {
            HStack(spacing: 5) {
                VStack(alignment: .center, spacing: 0) {
                    Stepper(
                        "",
                        value: Binding<Double>(
                            get: { Double(defaultTabWidth) },
                            set: { defaultTabWidth = Int($0) }
                        ),
                        in: 1...16,
                        step: 1,
                        format: .number
                    )
                    .labelsHidden()
                    Text("Tab")
                        .foregroundColor(.primary)
                        .font(.footnote)
                }
                .help("The visual width of tab characters")
                VStack(alignment: .center, spacing: 0) {
                    Stepper(
                        "",
                        value: Binding<Double>(
                            get: { Double(indentOption.spaceCount) },
                            set: { indentOption.spaceCount = Int($0) }
                        ),
                        in: 1...10,
                        step: 1,
                        format: .number
                    )
                    .labelsHidden()
                    Text("Indent")
                        .foregroundColor(.primary)
                        .font(.footnote)
                }
                .help("The number of spaces to insert when the tab key is pressed.")
            }
        }
        .onChange(of: defaultTabWidth) { _, newValue in
            file?.fileDocument?.defaultTabWidth = newValue == textEditing.defaultTabWidth ? nil : newValue
        }
    }

    private var wrapLinesToggle: some View {
        Toggle("Wrap lines", isOn: $wrapLines)
            .onChange(of: wrapLines) { _, newValue in
                file?.fileDocument?.wrapLines = newValue == textEditing.wrapLinesToEditorWidth ? nil : newValue
            }
    }

    private func chooseNewFileLocation() -> URL? {
        guard let file else { return nil }
        let dialogue = NSSavePanel()
        dialogue.title = "Save File"
        dialogue.directoryURL = file.url.deletingLastPathComponent()
        dialogue.nameFieldStringValue = file.name
        if dialogue.runModal() == .OK {
            return dialogue.url
        } else {
            return nil
        }
    }
}

/// The language selector in the file inspector.
///
/// Lists the catalog's languages grouped by source (built-in, extension) with a search field, and
/// shows the contributing extension's name and version for contributed languages. Inputs are plain
/// values so the same view renders both the workspace catalog and the built-in fallback.
private struct LanguageSelector: View {
    let builtInLanguages: [CodeLanguage]
    let contributedLanguages: [LanguageCatalogStore.ContributedLanguage]

    @Binding var selection: CodeLanguage?

    @State private var search = ""

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var visibleBuiltIn: [CodeLanguage] {
        guard !query.isEmpty else { return builtInLanguages }
        // Keep the current selection visible even when it does not match, so the picker keeps a label.
        return builtInLanguages.filter { matches($0.id.rawValue) || matches($0.tsName) || $0 == selection }
    }

    private var visibleContributed: [LanguageCatalogStore.ContributedLanguage] {
        guard !query.isEmpty else { return contributedLanguages }
        return contributedLanguages.filter {
            matches($0.id) || matches($0.language.tsName) || matches($0.extensionName) || $0.language == selection
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search Languages", text: $search)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $selection) {
                Text("Default - Detected").tag(nil as CodeLanguage?)

                if !visibleBuiltIn.isEmpty {
                    Section("Built-in") {
                        ForEach(visibleBuiltIn, id: \.id) { language in
                            Text(language.id.rawValue.capitalized)
                                .tag(language as CodeLanguage?)
                        }
                    }
                }

                if !visibleContributed.isEmpty {
                    Section("Extensions") {
                        ForEach(visibleContributed) { entry in
                            Text(label(for: entry))
                                .tag(entry.language as CodeLanguage?)
                        }
                    }
                }
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        text.lowercased().contains(query)
    }

    private func label(for entry: LanguageCatalogStore.ContributedLanguage) -> String {
        let version = entry.extensionVersion.map { " \($0)" } ?? ""
        return "\(entry.language.tsName) — \(entry.extensionName)\(version)"
    }
}

/// Observes a workspace ``LanguageCatalogStore`` and forwards its language groups to
/// ``LanguageSelector``, so the inspector refreshes when an extension pack is installed, enabled,
/// disabled or reloaded.
private struct ObservedLanguageSelector: View {
    @ObservedObject var store: LanguageCatalogStore
    @Binding var selection: CodeLanguage?

    var body: some View {
        LanguageSelector(
            builtInLanguages: store.builtInLanguages,
            contributedLanguages: store.contributedLanguages,
            selection: $selection
        )
        .onChange(of: store.version) { _, _ in
            guard let selection else { return }
            let stillAvailable = store.builtInLanguages.contains { $0.id == selection.id }
                || store.contributedLanguages.contains { $0.language.id == selection.id }
            if !stillAvailable {
                self.selection = nil
            }
        }
    }
}
