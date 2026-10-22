//
//  HelpCommands.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 14/03/2023.
//

import SwiftUI

struct HelpCommands: Commands {
    @Environment(\.openWindow)
    var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Knowledge Base") {
                openWindow(sceneID: .knowledge)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Search Knowledge Base…") {
                NSApp.sendAction(#selector(CodeEditWindowController.openKnowledgeSearch(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Divider()

            Button("What's New in Nodal IDE") {

            }
            .disabled(true)

            Button("Release Notes") {
            }
            .disabled(true)

            Button("Report an Issue") {
                NSApp.sendAction(#selector(AppDelegate.openFeedback(_:)), to: nil, from: nil)
            }
        }
    }
}
