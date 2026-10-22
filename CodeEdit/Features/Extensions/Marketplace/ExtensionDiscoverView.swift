import SwiftUI

struct ExtensionDiscoverView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @State private var selection: ExtensionCatalogCandidateID?
    @State private var isShowingSourcePicker = false

    let onShowSources: () -> Void

    init(onShowSources: @escaping () -> Void = {}) {
        self.onShowSources = onShowSources
    }

    var body: some View {
        HStack(spacing: 0) {
            candidateList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Discover")
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
                .disabled(marketplace.isRefreshing || !marketplace.hasRefreshableSources)
                .accessibilityLabel("Refresh extension catalogs")
                .help("Refresh trusted, enabled sources")
            }
        }
        .task { await marketplace.loadCachedCatalogs() }
    }

    private var candidateList: some View {
        VStack(spacing: 0) {
            if marketplace.isLoadingCachedCatalogs, marketplace.candidates.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading cached catalogs…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                Divider()
            } else if let healthNotice = marketplace.sourceHealth.notice {
                SourceStatusBanner(
                    title: healthNotice.title,
                    detail: healthNotice.detail,
                    onRefresh: { Task { await marketplace.refreshAll() } },
                    onShowSources: onShowSources,
                    canRefresh: marketplace.hasRefreshableSources && !marketplace.isRefreshing
                )
                Divider()
            }

            List(selection: $selection) {
                if marketplace.candidates.isEmpty {
                    discoverEmptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(marketplace.candidates) { candidate in
                        ExtensionCatalogRow(candidate: candidate)
                            .tag(Optional(candidate.id))
                    }
                }
            }
            .listStyle(.inset)
        }
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
           let candidate = marketplace.candidate(for: selection) {
            ExtensionCatalogDetailView(candidate: candidate)
        } else {
            ExtensionEmptyState(
                systemImage: "puzzlepiece.extension",
                title: "Select an Extension",
                message: "Choose an extension from the list to inspect its versions, publisher, and source."
            )
        }
    }

    private var discoverEmptyState: ExtensionEmptyState {
        if marketplace.sources.isEmpty {
            return ExtensionEmptyState(
                systemImage: "square.grid.2x2",
                title: "Discover Extensions",
                message: "Add a catalog source to browse extensions from a publisher you choose.",
                primaryAction: .init("Add Source…", systemImage: "plus") {
                    isShowingSourcePicker = true
                }
            )
        }

        if !marketplace.hasRefreshableSources {
            let message = marketplace.hasEnabledUntrustedSources
                ? "Review and trust a source in Sources to see its catalog here."
                : "Enable a source in Sources to see its catalog here."
            return ExtensionEmptyState(
                systemImage: "hand.raised",
                title: "No Trusted Sources",
                message: message,
                primaryAction: .init("Manage Sources", systemImage: "externaldrive") {
                    onShowSources()
                }
            )
        }

        if marketplace.indexedCandidateCount == 0 {
            if marketplace.hasSearchOrSourceFilter {
                return ExtensionEmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "No Matching Extensions",
                    message: "The current search or source filter has no extensions. Clear filters " +
                        "to browse all sources, or refresh a trusted catalog.",
                    primaryAction: .init("Clear Filters", systemImage: "xmark.circle") {
                        clearFilters()
                    },
                    secondaryAction: .init("Refresh Catalogs", systemImage: "arrow.clockwise") {
                        Task { await marketplace.refreshAll() }
                    }
                )
            }

            return ExtensionEmptyState(
                systemImage: "arrow.clockwise",
                title: "No Catalog Data Yet",
                message: "Refresh a trusted source to load its extension catalog.",
                primaryAction: .init("Refresh Catalogs", systemImage: "arrow.clockwise") {
                    Task { await marketplace.refreshAll() }
                },
                secondaryAction: .init("Manage Sources", systemImage: "externaldrive") {
                    onShowSources()
                }
            )
        }

        return ExtensionEmptyState(
            systemImage: "magnifyingglass",
            title: "No Matching Extensions",
            message: "No extension matches the current search. Try a different term or clear the " +
                "search field.",
            primaryAction: .init("Clear Filters", systemImage: "xmark.circle") {
                clearFilters()
            },
            secondaryAction: .init("Manage Sources", systemImage: "externaldrive") {
                onShowSources()
            }
        )
    }

    private func clearFilters() {
        marketplace.searchText = ""
        marketplace.selectedSourceID = nil
    }

}

struct SourceStatusBanner: View {
    let title: String
    let detail: String
    let onRefresh: () -> Void
    let onShowSources: () -> Void
    let canRefresh: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", action: onRefresh)
                .disabled(!canRefresh)
            Button("Manage Sources", action: onShowSources)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
        .accessibilityElement(children: .contain)
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
                if marketplace.isShowingCachedData(for: candidate.sourceID) {
                    Label("Cached", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
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
        .accessibilityLabel(accessibilityLabel)
    }

    private var sourceName: String {
        marketplace.sourceName(for: candidate.sourceID)
    }

    private var accessibilityLabel: String {
        var label = "\(candidate.entry.name), version \(candidate.version), " +
            "by \(candidate.entry.publisher), source \(sourceName)"
        if marketplace.isShowingCachedData(for: candidate.sourceID) {
            label += ", cached catalog"
        }
        return label
    }
}
