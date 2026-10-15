//
//  RuntimeCommands.swift
//  CodeEdit
//
//  The "Runtimes" menu: open the Runtime Manager window.
//

import SwiftUI

struct RuntimeCommands: Commands {
    @Environment(\.openWindow)
    var openWindow

    var body: some Commands {
        CommandMenu("Runtimes") {
            Button("Manage Runtimes…") {
                openWindow(sceneID: .runtimes)
            }
        }
    }
}
