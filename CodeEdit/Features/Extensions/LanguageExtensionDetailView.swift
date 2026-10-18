//
//  LanguageExtensionDetailView.swift
//  CodeEdit
//

import SwiftUI
import AppKit

/// Detail view for a declarative language extension in the Extensions window.
struct LanguageExtensionDetailView: View {
    let ext: InstalledLanguageExtension

    @ObservedObject private var languageManager = LanguageExtensionManager.shared

    @AppSettings(\.extensions.disabledExtensions)
    var disabledExtensions

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
            AppServices.languageProviderRegistry.reloadAllExtensions()
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
