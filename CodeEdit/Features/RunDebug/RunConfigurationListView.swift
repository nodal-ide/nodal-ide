//
//  RunConfigurationListView.swift
//  CodeEdit
//
//  Lists run configurations in the workspace settings, with an editor sheet.
//

import SwiftUI

struct RunConfigurationListView: View {
    @ObservedObject var store: RunConfigurationStore
    @Binding var selectedID: UUID?
    @Binding var showEditor: Bool
    var site: LocalSiteSettings?

    var body: some View {
        if store.configurations.isEmpty {
            Text("No run configurations")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(store.configurations) { configuration in
                HStack {
                    Image(systemName: configuration.kind.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(configuration.name)
                    Spacer()
                    Text(subtitle(for: configuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedID = configuration.id
                    showEditor = true
                }
                .contextMenu {
                    Button("Edit") {
                        selectedID = configuration.id
                        showEditor = true
                    }
                    Button("Delete", role: .destructive) {
                        store.remove(configuration.id)
                    }
                }
            }
        }
    }

    private func subtitle(for configuration: RunConfiguration) -> String {
        guard configuration.kind == .site else {
            return configuration.command
        }
        let domain = site?.domain.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return domain.isEmpty ? "Local domain" : domain
    }
}

struct RunConfigurationEditorSheet: View {
    @Environment(\.dismiss)
    private var dismiss
    @ObservedObject var store: RunConfigurationStore

    @State private var configuration: RunConfiguration
    private let isNew: Bool
    private let taskNames: [String]
    private let site: LocalSiteSettings?
    private let onEditLocalDomain: (() -> Void)?

    init(
        store: RunConfigurationStore,
        configuration: RunConfiguration?,
        taskNames: [String],
        site: LocalSiteSettings? = nil,
        onEditLocalDomain: (() -> Void)? = nil
    ) {
        self.store = store
        self.isNew = configuration == nil
        self._configuration = State(initialValue: configuration ?? RunConfiguration())
        self.taskNames = taskNames
        self.site = site
        self.onEditLocalDomain = onEditLocalDomain
    }

    var body: some View {
        VStack(spacing: 0) {
            RunConfigurationFormView(
                configuration: $configuration,
                taskNames: taskNames,
                site: site,
                onEditLocalDomain: {
                    dismiss()
                    onEditLocalDomain?()
                }
            )
            Divider()
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    if isNew {
                        store.add(configuration)
                    } else {
                        store.update(configuration)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(configuration.isInvalid)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}
