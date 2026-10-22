import SwiftUI

struct ExtensionUpdatesView: View {
    @EnvironmentObject private var languageManager: LanguageExtensionManager

    var body: some View {
        ContentUnavailableView {
            Label("Update Discovery Coming Soon", systemImage: "arrow.down.circle")
        } description: {
            if languageManager.extensions.isEmpty {
                Text("Updates will appear here after you install extensions from a source.")
            } else {
                Text(
                    "Installed extensions do not yet have marketplace provenance. " +
                        "Update discovery will follow source-backed installation."
                )
            }
        } actions: {
            Text("Extensions installed from folders or archives remain available in Installed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Updates")
    }
}
