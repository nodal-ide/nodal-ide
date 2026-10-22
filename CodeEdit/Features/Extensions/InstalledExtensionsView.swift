//
//  InstalledExtensionsView.swift
//  CodeEdit
//
//  Installed extension list with a detail pane.
//

import SwiftUI

/// Split view for the Installed destination: the existing list on the left and the selected
/// extension's detail on the right.
struct InstalledExtensionsView: View {
    @Binding var selection: Set<ExtensionItem>
    var onShowDiscover: () -> Void = {}

    var body: some View {
        HSplitView {
            ExtensionsListView(selection: $selection, onShowDiscover: onShowDiscover)
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)

            detail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var detail: some View {
        if selection.count == 1, let item = selection.first {
            switch item {
            case .language(let ext):
                LanguageExtensionDetailView(ext: ext)
            case .app(let info):
                ExtensionDetailView(ext: info)
            }
        } else {
            ExtensionEmptyState(
                systemImage: "sidebar.left",
                title: "Select an Extension",
                message: "Choose an installed extension to see its details and project activation."
            )
        }
    }
}
