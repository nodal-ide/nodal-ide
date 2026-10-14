//
//  MainCommands.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI
import Sparkle

struct MainCommands: Commands {
    @Environment(\.openWindow)
    var openWindow

    @UpdatingWindowController var windowController

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CodeEdit") {
                openWindow(sceneID: .about)
            }

            Button("Check for updates...") {
                NSApp.sendAction(#selector(SPUStandardUpdaterController.checkForUpdates(_:)), to: nil, from: nil)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(sceneID: .settings)
            }
            .keyboardShortcut(",")

            Button("Project Settings...") {
                NSApp.sendAction(#selector(CodeEditWindowController.openWorkspaceSettings(_:)), to: nil, from: nil)
            }
            .disabled(windowController?.workspace == nil)
        }
    }
}
