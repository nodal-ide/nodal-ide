import SwiftUI

struct ExtensionManagerWindow: Scene {
    @ObservedObject var manager = AppServices.extensionManager
    @ObservedObject var languageManager = AppServices.languageExtensionManager

    @State private var installedSelection = Set<ExtensionItem>()
    @State private var destination: ExtensionManagerDestination = .discover
    @StateObject private var marketplace = ExtensionMarketplaceViewModel()

    var body: some Scene {
        Window("Extensions", id: SceneID.extensions.rawValue) {
            NavigationSplitView {
                List(selection: $destination) {
                    Section("Marketplace") {
                        ForEach(ExtensionManagerDestination.marketplaceDestinations) { item in
                            Label(item.title, systemImage: item.symbol)
                                .tag(item)
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
            .frame(minWidth: 820, minHeight: 520)
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch destination {
        case .discover:
            ExtensionDiscoverView()
        case .installed:
            ExtensionsListView(selection: $installedSelection)
        case .sources:
            ExtensionSourcesView()
        case .updates:
            ExtensionUpdatesView()
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
