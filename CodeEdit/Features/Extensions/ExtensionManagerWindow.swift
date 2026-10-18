//
//  ExtensionManagerWindow.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 24/03/2023.
//

import SwiftUI

struct ExtensionManagerWindow: Scene {
    @ObservedObject var manager = AppServices.extensionManager
    @ObservedObject var languageManager = AppServices.languageExtensionManager

    @State var selection = Set<ExtensionItem>()

    var body: some Scene {
        Window("Extensions", id: SceneID.extensions.rawValue) {
            NavigationSplitView {
                ExtensionsListView(selection: $selection)
            } detail: {
                Group {
                    if selection.isEmpty {
                        Text("Select an extension")
                    } else if selection.count == 1, let item = selection.first {
                        switch item {
                        case .app(let info):
                            ExtensionDetailView(ext: info)
                        case .language(let ext):
                            LanguageExtensionDetailView(ext: ext)
                        }
                    } else {
                        Text("\(selection.count) selected")
                    }
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: 480)
            }
            .environmentObject(manager)
            .environmentObject(languageManager)
            .focusedObject(manager)
        }
    }
}
