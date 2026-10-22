//
//  LanguageExtensionDetailView.swift
//  CodeEdit
//

import SwiftUI
import AppKit
import CodeEditLang

/// Detail view for a declarative language extension in the Extensions window.
struct LanguageExtensionDetailView: View {
    let ext: InstalledLanguageExtension

    @ObservedObject private var languageManager = AppServices.languageExtensionManager

    @AppSettings(\.extensions.disabledExtensions)
    var disabledExtensions

    /// The result of loading this pack's syntax contributions against the built-in catalog.
    ///
    /// Other enabled installed packs are loaded too, so duplicate language ids and detection keys
    /// between packs are reported here as well. Workspace packs are workspace-scoped and resolved by
    /// ``LanguageCatalogStore``, so they are not shown in this app-global window.
    @State private var syntaxOutcome: SyntaxContributionLoader.PackOutcome?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: ext.icon)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ext.name)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let version = ext.version {
                            labeled("Version", version)
                        }
                        if let author = ext.manifest.author {
                            labeled("Author", author)
                        }
                        if let framework = ext.frameworkName {
                            labeled("Framework", framework)
                        }
                        if let languages = ext.manifest.languages, !languages.isEmpty {
                            labeled("Languages", languages.joined(separator: ", "))
                        }
                        if let urlString = ext.manifest.url, let url = URL(string: urlString) {
                            Link(urlString, destination: url)
                                .font(.callout)
                        }
                    }
                }

                if let description = ext.manifest.description, !description.isEmpty {
                    Text(description)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                Toggle("Enabled", isOn: enabledBinding)
            }

            Section("Syntax") {
                if let outcome = syntaxOutcome {
                    syntaxContent(outcome)
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking syntax contributions…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ext.root])
                    }
                    Spacer()
                    Button(role: .destructive) {
                        try? languageManager.remove(ext)
                    } label: {
                        Text("Remove Extension")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationSubtitle(ext.name)
        .textSelection(.enabled)
        .task(id: ext.id) {
            let packs = languageManager.extensions.filter {
                $0.id == ext.id || LanguageExtensionActivation.isEnabled($0)
            }
            let outcomes = SyntaxContributionLoader.resolveConflicts(
                SyntaxContributionLoader().load(packs, base: .builtIn)
            )
            syntaxOutcome = outcomes.first { $0.extensionID == ext.id }
        }
    }

    // MARK: - Syntax status

    @ViewBuilder
    private func syntaxContent(_ outcome: SyntaxContributionLoader.PackOutcome) -> some View {
        if outcome.languages.isEmpty, outcome.issues.isEmpty {
            Text("This extension does not contribute syntax.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(outcome.languages, id: \.id) { language in
                labeled("Language", language.tsName)
            }

            if outcome.issues.isEmpty {
                Label("No syntax problems found.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(Array(outcome.issues.enumerated()), id: \.offset) { _, issue in
                    issueRow(issue)
                }
            }
        }
    }

    @ViewBuilder
    private func issueRow(_ issue: LanguageExtensionIssue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? .red : .yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message)
                if let location = issue.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            !disabledExtensions.contains(ext.id)
        } set: { enabled in
            var list = disabledExtensions
            list.removeAll { $0 == ext.id }
            if !enabled {
                list.append(ext.id)
            }
            disabledExtensions = list
            AppServices.languageExtensionManager.reloadAll()
        }
    }

    @ViewBuilder
    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .font(.callout)
    }
}
