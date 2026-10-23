import SwiftUI

struct ExtensionManagerWindow: Scene {
    @ObservedObject var manager = AppServices.extensionManager
    @ObservedObject var languageManager = AppServices.languageExtensionManager

    @State private var installedSelection = Set<ExtensionItem>()
    @State private var destination: ExtensionManagerDestination = .discover
    @StateObject private var marketplace = ExtensionMarketplaceViewModel()
    @StateObject private var installation = ExtensionInstallationViewModel()

    var body: some Scene {
        Window("Extensions", id: SceneID.extensions.rawValue) {
            NavigationSplitView {
                List(selection: $destination) {
                    Section("Marketplace") {
                        ForEach(ExtensionManagerDestination.marketplaceDestinations) { item in
                            if item == .updates, availableUpdateCount > 0 {
                                Label(item.title, systemImage: item.symbol)
                                    .tag(item)
                                    .badge(availableUpdateCount)
                            } else {
                                Label(item.title, systemImage: item.symbol)
                                    .tag(item)
                            }
                        }
                    }
                    Section("Manage") {
                        Label(
                            ExtensionManagerDestination.installed.title,
                            systemImage: ExtensionManagerDestination.installed.symbol
                        )
                            .tag(ExtensionManagerDestination.installed)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Extensions")
            } detail: {
                destinationView
            }
            .environmentObject(manager)
            .environmentObject(languageManager)
            .environmentObject(marketplace)
            .environmentObject(installation)
            .frame(minWidth: 960, minHeight: 520)
            .task { await marketplace.loadCachedCatalogs() }
        }
    }

    private var availableUpdateCount: Int {
        ExtensionUpdateIndex(
            installed: languageManager.extensions,
            catalogs: marketplace.catalogs,
            sources: marketplace.sources,
            appVersion: Bundle.versionString
        )
        .availableUpdates
        .count
    }

    @ViewBuilder private var destinationView: some View {
        switch destination {
        case .discover:
            ExtensionDiscoverView(onShowSources: { destination = .sources })
        case .installed:
            InstalledExtensionsView(
                selection: $installedSelection,
                onShowDiscover: { destination = .discover }
            )
        case .sources:
            ExtensionSourcesView()
        case .updates:
            ExtensionUpdatesView(
                onShowDiscover: { destination = .discover },
                onShowSources: { destination = .sources }
            )
        }
    }
}

enum ExtensionManagerDestination: String, CaseIterable, Identifiable, Hashable {
    case discover
    case installed
    case sources
    case updates

    static let marketplaceDestinations: [Self] = [.discover, .updates, .sources]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .installed: "Installed"
        case .sources: "Sources"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .discover: "square.grid.2x2"
        case .installed: "puzzlepiece.extension"
        case .sources: "externaldrive"
        case .updates: "arrow.down.circle"
        }
    }
}
