import SwiftUI

struct ExtensionDiscoverView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @State private var selection: ExtensionCatalogCandidateID?
    @State private var isShowingSourcePicker = false

    var body: some View {
        HStack(spacing: 0) {
            candidateList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $marketplace.searchText, prompt: "Extensions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Source", selection: $marketplace.selectedSourceID) {
                    Text("All Sources").tag(nil as ExtensionSourceID?)
                    ForEach(marketplace.sources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Filter extensions by source")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await marketplace.refreshAll() }
                } label: {
                    if marketplace.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh Catalogs", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(marketplace.isRefreshing || marketplace.sources.isEmpty)
                .help("Refresh trusted, enabled sources")
            }
        }
        .task { await marketplace.loadCachedCatalogs() }
    }

    private var candidateList: some View {
        List(selection: $selection) {
            if marketplace.candidates.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "puzzlepiece.extension")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if marketplace.sources.isEmpty {
                        Button("Add Source…") { isShowingSourcePicker = true }
                    } else if marketplace.sources.contains(where: { $0.isTrusted && $0.isEnabled }) {
                        Button("Refresh Catalogs") { Task { await marketplace.refreshAll() } }
                    }
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(marketplace.candidates) { candidate in
                    ExtensionCatalogRow(candidate: candidate)
                        .tag(Optional(candidate.id))
                }
            }
        }
        .listStyle(.inset)
        .sheet(isPresented: $isShowingSourcePicker) {
            AddExtensionSourceSheet()
                .environmentObject(marketplace)
        }
        .onChange(of: marketplace.candidates.map(\.id)) { _, candidateIDs in
            if let selection, !candidateIDs.contains(selection) { self.selection = nil }
            if selection == nil { selection = candidateIDs.first }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection,
           let candidate = marketplace.candidates.first(where: { $0.id == selection }) {
            ExtensionCatalogDetailView(candidate: candidate)
        } else {
            ContentUnavailableView("Select an Extension", systemImage: "puzzlepiece.extension")
        }
    }

    private var emptyTitle: String {
        marketplace.sources.isEmpty ? "No Extension Sources" : "No Extensions Found"
    }

    private var emptyDescription: String {
        if marketplace.sources.isEmpty {
            return "Add a trusted catalog source to discover extensions."
        }
        if marketplace.sources.contains(where: { !$0.isTrusted && $0.isEnabled }) {
            return "Review and trust a source in Sources, then refresh its catalog."
        }
        return "Refresh a trusted source or change your search and source filters."
    }
}

private struct ExtensionCatalogRow: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    let candidate: ExtensionCatalogCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.entry.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(candidate.version)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(candidate.entry.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(candidate.entry.publisher)
                Text("·")
                Text(sourceName)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(candidate.entry.name), version \(candidate.version), " +
                "by \(candidate.entry.publisher), source \(sourceName)"
        )
    }

    private var sourceName: String {
        marketplace.sourceName(for: candidate.sourceID)
    }
}

private struct ExtensionCatalogDetailView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    let candidate: ExtensionCatalogCandidate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(candidate.entry.name)
                        .font(.largeTitle.weight(.semibold))
                    Text(candidate.entry.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Label(candidate.entry.publisher, systemImage: "person")
                        .font(.subheadline)
                }

                GroupBox("Catalog Details") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        detailRow("Extension ID", candidate.extensionID)
                        detailRow("Latest Version", candidate.entry.latest)
                        detailRow("Source", sourceName)
                        if let homepage = candidate.entry.url {
                            GridRow {
                                Text("Website").foregroundStyle(.secondary)
                                Link(homepage.host ?? homepage.absoluteString, destination: homepage)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Available Versions") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(candidate.entry.versions.keys.sorted(by: versionOrder), id: \.self) { version in
                            HStack {
                                Text(version).font(.body.monospaced())
                                if version == candidate.entry.latest {
                                    Text("Latest").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let publishedAt = candidate.entry.versions[version]?.publishedAt {
                                    Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label(
                    "Install and package capability details will be available in the next marketplace phase.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var sourceName: String {
        marketplace.sourceName(for: candidate.sourceID)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func versionOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == candidate.entry.latest { return true }
        if rhs == candidate.entry.latest { return false }
        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }
}
