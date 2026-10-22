//
//  ExtensionRegistryManageView.swift
//  CodeEdit
//

import AppKit
import SwiftUI

struct ExtensionRegistryManageView: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @AppSettings(\.extensions.registry)
    private var registry

    @State private var snapshot: ExtensionRegistrySnapshot?
    @State private var isLoading = false
    @State private var isRetrying = false
    @State private var isShowingSetup = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Extension Registry")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(20)
            Divider()

            if let registry {
                registryContent(registry)
            } else {
                emptyContent
            }
        }
        .frame(width: 620, height: 540)
        .task { await load() }
        .onChange(of: registry) {
            Task { await load() }
        }
        .sheet(isPresented: $isShowingSetup) {
            ExtensionRegistrySetupView(configuration: registry)
                .environmentObject(marketplace)
        }
    }

    private func registryContent(_ registry: ExtensionRegistryConfiguration) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("Registry") {
                    labeled("Name", registry.name)
                    labeled("Folder", registry.workingCopyPath)
                    labeled("Branch", snapshot?.branch ?? registry.branch)
                    labeled("Remote", snapshot?.remoteURL ?? "No origin remote")
                    labeled("Catalog", registry.catalogURL ?? "Not hosted yet")
                    if let count = snapshot?.extensionCount {
                        labeled("Extensions", "\(count)")
                    }
                }
                workingTreeSection
                if let pending = snapshot?.pendingPush {
                    pendingSection(pending, registry: registry)
                }
                if errorMessage != nil {
                    errorSection
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if isLoading || isRetrying {
                    ProgressView().controlSize(.small)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(filePath: registry.workingCopyPath, directoryHint: .isDirectory)
                    ])
                }
                Button("Recheck") { Task { await load() } }
                    .disabled(isLoading)
                Spacer()
                Button("Edit…") { isShowingSetup = true }
            }
            .padding(20)
        }
    }

    @ViewBuilder private var workingTreeSection: some View {
        Section("Working Tree") {
            if let snapshot {
                if snapshot.changes.isEmpty {
                    Label("Clean", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "\(snapshot.changes.count) uncommitted change"
                            + (snapshot.changes.count == 1 ? "" : "s"),
                        systemImage: "pencil.circle"
                    )
                    ForEach(snapshot.changes.prefix(8)) { change in
                        Text("\(change.code)  \(change.path)")
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    if snapshot.changes.count > 8 {
                        Text("…and \(snapshot.changes.count - 8) more")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func pendingSection(
        _ pending: ExtensionPublishJournal,
        registry: ExtensionRegistryConfiguration
    ) -> some View {
        Section("Pending Push") {
            labeled("Extension", pending.extensionID)
            labeled("Version", pending.version)
            labeled("Commit", String(pending.commitSHA.prefix(12)))
            Text("The commit exists locally. Retry pushes only that commit.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry Push") { retryPush(registry) }
                .disabled(isRetrying)
        }
    }

    @ViewBuilder private var errorSection: some View {
        Section {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No Publishing Registry")
                .font(.title3.weight(.semibold))
            Text("Create a Git-backed registry to package, review, and publish extensions.")
                .foregroundStyle(.secondary)
            Button("Create Registry…") { isShowingSetup = true }
            Spacer()
        }
    }

    @ViewBuilder
    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .font(.callout)
    }

    private func load() async {
        guard let registry else {
            snapshot = nil
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            snapshot = try await AppServices.extensionRegistryService.inspect(configuration: registry)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func retryPush(_ registry: ExtensionRegistryConfiguration) {
        isRetrying = true
        errorMessage = nil
        Task {
            do {
                _ = try await AppServices.extensionRegistryService.retryPendingPush(
                    configuration: registry
                )
                snapshot = try await AppServices.extensionRegistryService.inspect(
                    configuration: registry
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isRetrying = false
        }
    }
}
