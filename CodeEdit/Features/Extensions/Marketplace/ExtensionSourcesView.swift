import SwiftUI

struct ExtensionSourcesView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @AppSettings(\.extensions.registry)
    private var registry
    @State private var isShowingAddSource = false
    @State private var isShowingRegistrySetup = false
    @State private var isShowingRegistryManage = false
    @State private var isShowingPublish = false
    @State private var sourceToEdit: ExtensionSource?
    @State private var sourceToTrust: ExtensionSource?
    @State private var sourceToRemove: ExtensionSource?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Publishing") {
                    ExtensionRegistrySourcesRow(
                        registry: registry,
                        onCreate: { isShowingRegistrySetup = true },
                        onManage: { isShowingRegistryManage = true },
                        onPublish: { isShowingPublish = true }
                    )
                }

                if marketplace.sources.isEmpty {
                    ExtensionEmptyState(
                        systemImage: "externaldrive.badge.plus",
                        title: "No Extension Sources",
                        message: "Add a static HTTPS catalog or Git repository to browse extensions " +
                            "from a publisher you choose. New sources stay untrusted until you review " +
                            "and trust them.",
                        primaryAction: .init("Add Source…", systemImage: "plus") {
                            isShowingAddSource = true
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(marketplace.sources) { source in
                        ExtensionSourceRow(
                            source: source,
                            state: marketplace.state(for: source.id),
                            onEdit: { sourceToEdit = source },
                            onTrust: { sourceToTrust = source },
                            onRemove: { sourceToRemove = source },
                            onRefresh: { Task { await marketplace.refresh(source) } },
                            onEnabledChange: { enabled in
                                do {
                                    try marketplace.setEnabled(enabled, for: source)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        )
                    }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if registry == nil {
                        Button("Create Registry…", systemImage: "shippingbox") {
                            isShowingRegistrySetup = true
                        }
                    } else {
                        Button("Manage Registry…", systemImage: "shippingbox") {
                            isShowingRegistryManage = true
                        }
                    }
                    Button("Package & Publish Extension…", systemImage: "paperplane") {
                        isShowingPublish = true
                    }
                } label: {
                    Label("Registry", systemImage: "shippingbox")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Source…", systemImage: "plus") { isShowingAddSource = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await marketplace.refreshAll() }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(
                    marketplace.isRefreshing
                        || !marketplace.sources.contains(where: { $0.isTrusted && $0.isEnabled })
                )
            }
        }
        .sheet(isPresented: $isShowingAddSource) {
            AddExtensionSourceSheet()
                .environmentObject(marketplace)
        }
        .sheet(isPresented: $isShowingRegistrySetup) {
            ExtensionRegistrySetupView(configuration: registry)
                .environmentObject(marketplace)
        }
        .sheet(isPresented: $isShowingRegistryManage) {
            ExtensionRegistryManageView()
                .environmentObject(marketplace)
        }
        .sheet(isPresented: $isShowingPublish) {
            ExtensionPublishView(initialExtension: nil)
        }
        .sheet(item: $sourceToEdit) { source in
            AddExtensionSourceSheet(source: source)
                .environmentObject(marketplace)
        }
        .confirmationDialog(
            "Trust \(sourceToTrust?.name ?? "this source")?",
            isPresented: Binding(
                get: { sourceToTrust != nil },
                set: { if !$0 { sourceToTrust = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Trust Source", role: .destructive) {
                guard let source = sourceToTrust else { return }
                do {
                    try marketplace.setTrusted(true, for: source)
                } catch {
                    errorMessage = error.localizedDescription
                }
                sourceToTrust = nil
            }
        } message: {
            Text(
                "Trust allows Nodal IDE to fetch this source’s catalog and offer its packages. " +
                    "It does not verify publishers or approve native code. " +
                    "Installing an extension remains a separate action."
            )
        }
        .confirmationDialog(
            "Remove Source?",
            isPresented: Binding(
                get: { sourceToRemove != nil },
                set: { if !$0 { sourceToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Source", role: .destructive) {
                guard let source = sourceToRemove else { return }
                Task {
                    do {
                        try await marketplace.remove(source)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    sourceToRemove = nil
                }
            }
        } message: {
            Text(
                "The cached catalog will be removed. " +
                    "Extensions already installed from this source will remain installed."
            )
        }
        .alert(
            "Couldn’t Update Sources",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unexpected error occurred.")
        }
    }
}

private struct ExtensionSourceRow: View {
    let source: ExtensionSource
    let state: ExtensionSourceCatalogState
    let onEdit: () -> Void
    let onTrust: () -> Void
    let onRemove: () -> Void
    let onRefresh: () -> Void
    let onEnabledChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(source.name).font(.headline)
                Spacer()
                statusLabel
                Toggle("Enabled", isOn: Binding(
                    get: { source.isEnabled },
                    set: onEnabledChange
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Enable source \(source.name)")
            }
            Text(source.location.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
            HStack(spacing: 12) {
                Label(providerLabel, systemImage: providerSymbol)
                if source.providerID == .gitRepository {
                    Text(source.revision.map { "Revision \($0)" } ?? "Default branch")
                }
                stateDescription
                Spacer()
                Button("Edit", systemImage: "pencil", action: onEdit)
                if source.isTrusted {
                    Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                        .disabled(!source.isEnabled)
                } else {
                    Button("Trust…", action: onTrust)
                        .disabled(!source.isEnabled)
                }
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            }
            .font(.caption)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var statusLabel: some View {
        switch state {
        case .idle:
            Label("Not refreshed", systemImage: "clock")
        case .loading:
            Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
        case .fresh(let fetchedAt, _):
            Label(
                "Updated \(fetchedAt.formatted(.relative(presentation: .named)))",
                systemImage: "checkmark.circle"
            )
        case .stale(let fetchedAt, _):
            Label(
                "Stale · \(fetchedAt.formatted(.relative(presentation: .named)))",
                systemImage: "exclamationmark.circle"
            )
                .foregroundStyle(.orange)
        case .offline:
            Label("Offline", systemImage: "wifi.slash").foregroundStyle(.secondary)
        case .invalid:
            Label("Invalid", systemImage: "xmark.octagon").foregroundStyle(.red)
        case .untrusted:
            Label("Untrusted", systemImage: "hand.raised")
        case .disabled:
            Label("Disabled", systemImage: "pause.circle").foregroundStyle(.secondary)
        }
    }

    private var providerLabel: String {
        switch source.providerID {
        case .httpsStaticIndex: "HTTPS Static Index"
        case .gitRepository: "Git Repository"
        default: source.providerID.rawValue
        }
    }

    private var providerSymbol: String {
        switch source.providerID {
        case .httpsStaticIndex: "globe"
        case .gitRepository: "arrow.triangle.branch"
        default: "externaldrive"
        }
    }

    @ViewBuilder private var stateDescription: some View {
        switch state {
        case .fresh(_, let count):
            Text("\(count) extensions")
        case .stale(_, let failure):
            Text("Cached catalog · \(failure.label)").foregroundStyle(.orange)
        case .offline:
            Text("No catalog available while offline")
        case .invalid(let failure):
            Text(failure.label).foregroundStyle(.red)
        case .untrusted:
            Text("Trust required before fetching")
        case .disabled:
            Text("Enable to refresh")
        case .idle, .loading:
            EmptyView()
        }
    }
}

private extension ExtensionCatalogFailure {
    var label: String {
        switch self {
        case .invalidCatalog: "Invalid catalog"
        case .unavailable: "Refresh unavailable"
        case .providerUnavailable: "Provider unavailable"
        case .cacheUnavailable: "Cache unavailable"
        }
    }
}
