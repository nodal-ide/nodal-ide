//
//  LanguageExtensionDetailView.swift
//  CodeEdit
//

import SwiftUI
import AppKit
import CodeEditLang
import CodeEditLanguages

/// Detail view for a declarative language extension in the Extensions window.
struct LanguageExtensionDetailView: View {
    let ext: InstalledLanguageExtension

    @ObservedObject private var languageManager = AppServices.languageExtensionManager

    @AppSettings(\.extensions.disabledExtensions)
    var disabledExtensions

    @AppSettings(\.extensions.nativeGrammarConsent)
    var nativeGrammarConsent

    /// The result of loading this pack's syntax contributions against the built-in catalog.
    ///
    /// Other enabled installed packs are loaded too, so duplicate language ids and detection keys
    /// between packs are reported here as well. Workspace packs are workspace-scoped and resolved by
    /// ``LanguageCatalogStore``, so they are not shown in this app-global window.
    @State private var syntaxOutcome: SyntaxContributionLoader.PackOutcome?

    private var consent: NativeGrammarConsent { NativeGrammarConsent(recorded: nativeGrammarConsent) }

    private var nativeGrammarDeclarations: [NativeGrammarConsent.Declaration] {
        NativeGrammarConsent.declarations(in: ext)
    }

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

            if !nativeGrammarDeclarations.isEmpty {
                Section("Native Grammars") {
                    Text(
                        "This extension ships native parser code. It runs inside CodeEdit, so it is "
                            + "loaded only after you trust it."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    ForEach(nativeGrammarDeclarations, id: \.path) { declaration in
                        nativeGrammarRow(declaration)
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
        .task(id: taskID) {
            let packs = languageManager.extensions.filter {
                $0.id == ext.id || LanguageExtensionActivation.isEnabled($0)
            }
            let outcomes = SyntaxContributionLoader.resolveConflicts(
                SyntaxContributionLoader().load(
                    packs, base: .builtIn, consent: consent, validateNativeGrammarsFor: [ext.id]
                )
            )
            syntaxOutcome = outcomes.first { $0.extensionID == ext.id }
        }
    }

    /// Changes whenever this pack's native grammar consent changes, so the syntax check re-runs.
    private var taskID: String {
        let signature = nativeGrammarDeclarations
            .map { "\($0.path)=\(consent.recordedHash(packID: ext.id, grammarPath: $0.path) ?? "-")" }
            .joined(separator: "|")
        return "\(ext.id)#\(signature)"
    }

    // MARK: - Native grammars

    private struct GrammarStatus {
        let symbol: String
        let color: Color
        let label: String
    }

    private func grammarStatus(for declaration: NativeGrammarConsent.Declaration) -> GrammarStatus {
        guard consent.recordedHash(packID: ext.id, grammarPath: declaration.path) != nil else {
            return GrammarStatus(
                symbol: "lock.open",
                color: .secondary,
                label: "Not trusted — native code from this extension is not loaded."
            )
        }
        guard let url = LanguageExtensionPaths.resolve(declaration.path, in: ext.root) else {
            return GrammarStatus(symbol: "xmark.octagon.fill", color: .red, label: "Grammar file is missing.")
        }
        if let failure = NativeGrammarLoader.shared.failure(for: url) {
            return GrammarStatus(symbol: "xmark.octagon.fill", color: .red, label: failure.message)
        }
        guard let loaded = NativeGrammarLoader.shared.loadedHash(for: url) else {
            return GrammarStatus(symbol: "checkmark.shield", color: .green, label: "Trusted · not loaded yet.")
        }
        return GrammarStatus(
            symbol: "checkmark.shield",
            color: .green,
            label: "Trusted · loaded · SHA-256 \(loaded.prefix(12))…"
        )
    }

    @ViewBuilder
    private func nativeGrammarRow(_ declaration: NativeGrammarConsent.Declaration) -> some View {
        let status = grammarStatus(for: declaration)

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(declaration.symbol)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if consent.recordedHash(packID: ext.id, grammarPath: declaration.path) == nil {
                Button("Trust…") {
                    languageManager.trustNativeGrammars(of: ext)
                }
            } else {
                Button("Revoke") {
                    languageManager.revokeNativeGrammars(of: ext)
                }
            }
        }
        .font(.callout)
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
