import SwiftUI

struct ExtensionSourcesView: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @State private var isShowingAddSource = false
    @State private var sourceToEdit: ExtensionSource?
    @State private var sourceToTrust: ExtensionSource?
    @State private var sourceToRemove: ExtensionSource?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                if marketplace.sources.isEmpty {
                    ExtensionEmptyState(
                        systemImage: "externaldrive.badge.plus",
                        title: "No Extension Sources",
                        message: "Add a static HTTPS catalog to browse extensions from a publisher " +
                            "you choose. New sources stay untrusted until you review and trust them.",
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
                Label("HTTPS Static Index", systemImage: "globe")
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

struct AddExtensionSourceSheet: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var trustImmediately = false
    @State private var errorMessage: String?
    private let source: ExtensionSource?

    init(source: ExtensionSource? = nil) {
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _location = State(initialValue: source?.location.absoluteString ?? "")
        _trustImmediately = State(initialValue: source?.isTrusted ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(source == nil ? "Add Extension Source" : "Edit Extension Source")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name, prompt: Text("Team Registry"))
                TextField("Catalog URL", text: $location, prompt: Text("https://example.com/extensions.json"))
                    .textFieldStyle(.roundedBorder)
                if source == nil {
                    Toggle("Trust this source", isOn: $trustImmediately)
                }
            }
            Text(
                "A trusted source can provide catalog metadata and package downloads. " +
                    "Trust does not authenticate publishers or grant consent to native code. " +
                    "You can add the source without trusting it and review it first."
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(source == nil ? "Add Source" : "Save Changes") { saveSource() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || location.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func saveSource() {
        guard let url = URL(string: location.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Enter a valid HTTPS catalog URL."
            return
        }
        if let source {
            Task {
                do {
                    try await marketplace.updateSource(
                        source,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        location: url
                    )
                    dismiss()
                } catch ExtensionSourceCollectionError.invalidSourceLocation {
                    errorMessage = "The catalog URL must use HTTPS and cannot contain " +
                        "credentials, a query, or a fragment."
                } catch ExtensionSourceCollectionError.invalidSourceConfiguration {
                    errorMessage = "Choose a source name with 1–128 characters."
                } catch ExtensionSourceCollectionError.duplicateSourceLocation {
                    errorMessage = "A source with this catalog URL already exists."
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            return
        }
        do {
            try marketplace.addSource(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                location: url,
                trustImmediately: trustImmediately
            )
            dismiss()
        } catch ExtensionSourceCollectionError.invalidSourceLocation {
            errorMessage = "The catalog URL must use HTTPS and cannot contain credentials, a query, or a fragment."
        } catch ExtensionSourceCollectionError.invalidSourceConfiguration {
            errorMessage = "Choose a source name with 1–128 characters."
        } catch ExtensionSourceCollectionError.duplicateSourceLocation {
            errorMessage = "A source with this catalog URL already exists."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
