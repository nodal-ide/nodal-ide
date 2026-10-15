//
//  RuntimeManagerView.swift
//  CodeEdit
//
//  The Runtime Manager window: install/switch PHP & Node runtimes and package managers.
//

import SwiftUI

struct RuntimeManagerView: View {
    @StateObject private var model = RuntimeManagerViewModel()
    @ObservedObject private var tooling = RuntimeManager.shared.tooling

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RuntimeToolingBanner(tooling: tooling)
                    RuntimeVersionListView(model: model)
                    if model.selectedKind == .node {
                        RuntimePackageManagersView(model: model)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { await model.loadAll() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Picker("", selection: $model.selectedKind) {
                ForEach(RuntimeKind.manageable) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Runtime")
            .frame(maxWidth: 420)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter versions", text: $model.searchText)
                    .textFieldStyle(.plain)
                if model.loading.contains(model.selectedKind) {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.refreshCurrent() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload versions")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let def = model.defaultVersion {
                Label("Default: v\(def)", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No default version set").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.selection.count) selected").font(.callout).foregroundStyle(.secondary)
            Button("Uninstall") {
                Task { await model.uninstall(model.selectedRemovable) }
            }
            .disabled(model.selectedRemovable.isEmpty)
            Button("Install") {
                Task { await model.install(model.selectedInstallable) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedInstallable.isEmpty)
        }
        .padding(12)
    }
}

struct RuntimeVersionListView: View {
    @ObservedObject var model: RuntimeManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Versions").font(.headline)
                Spacer()
                if model.currentRows.isEmpty && !model.loading.contains(model.selectedKind) {
                    Button("Reload") { Task { await model.refreshCurrent() } }
                        .controlSize(.small)
                }
            }

            if model.currentRows.isEmpty && model.loading.contains(model.selectedKind) {
                loadingState
            } else if model.currentRows.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.currentRows) { row in
                        RuntimeVersionRowView(row: row, model: model)
                        if row.id != model.currentRows.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor))
                )
            }
        }
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading versions…")
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
            Text(model.searchText.isEmpty ? "No versions found" : "No versions match “\(model.searchText)”")
                .foregroundStyle(.secondary)
            Text("Check your connection, then reload.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct RuntimeVersionRowView: View {
    let row: RuntimeManagerViewModel.Row
    @ObservedObject var model: RuntimeManagerViewModel

    var body: some View {
        HStack(spacing: 12) {
            checkbox
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("v\(row.version)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    if row.isLTS {
                        RuntimeBadge(text: "LTS", color: .green)
                    }
                    if model.isDefault(row) {
                        RuntimeBadge(text: "Default", color: .blue)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection() }
    }

    private var checkbox: some View {
        Button {
            toggleSelection()
        } label: {
            Image(systemName: model.selection.contains(row.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.selection.contains(row.id) ? Color.accentColor : Color.secondary)
                .imageScale(.large)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isInstalled ? "Select installed v\(row.version)" : "Select v\(row.version) to install")
    }

    private var trailing: some View {
        Group {
            if row.isInstalled {
                Button(model.isDefault(row) ? "Default" : "Set Default") {
                    model.setDefault(model.isDefault(row) ? nil : row.version, kind: model.selectedKind)
                }
                .disabled(model.isDefault(row))
                .controlSize(.small)
            } else {
                Button("Install") {
                    Task { await model.install([row]) }
                }
                .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        if let installed = row.installed {
            var parts = ["Installed", installed.source.title]
            if let size = model.diskUsage[installed.id] {
                parts.append(RuntimeDiskUsage.formatted(size))
            }
            return parts.joined(separator: " · ")
        }
        if let date = row.releaseDate {
            return "Released " + date.formatted(date: .abbreviated, time: .omitted)
        }
        return "Not installed"
    }

    private func toggleSelection() {
        if model.selection.contains(row.id) {
            model.selection.remove(row.id)
        } else {
            model.selection.insert(row.id)
        }
    }
}

struct RuntimeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
