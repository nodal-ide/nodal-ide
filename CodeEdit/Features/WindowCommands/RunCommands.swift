//
//  RunCommands.swift
//  CodeEdit
//
//  The "Run" menu: run/stop the selected run configuration.
//

import SwiftUI

struct RunCommands: Commands {
    @UpdatingWindowController var windowController: CodeEditWindowController?

    private var runController: RunController? {
        windowController?.workspace?.runController
    }

    var body: some Commands {
        CommandMenu("Run") {
            Button("Run", systemImage: "play.fill") {
                runController?.runSelectedOrFirst()
            }
            .keyboardShortcut("r", modifiers: [.control, .option])
            .disabled(runController?.selectedConfiguration == nil)

            Button("Debug", systemImage: "ladybug.fill") {
                runController?.debugSelectedOrFirst()
            }
            .keyboardShortcut("d", modifiers: [.control, .option])
            .disabled(runController?.selectedConfiguration == nil)

            Button("Stop", systemImage: "stop.fill") {
                runController?.stop()
            }
            .disabled(!(runController?.isRunning ?? false))

            Divider()

            Button("Debug Current File", systemImage: "ladybug") {
                runController?.debugCurrentFile()
            }
            .disabled(runController?.hasActiveEditorFile != true)

            Button("Listen for Xdebug", systemImage: "antenna.radiowaves.left.and.right") {
                runController?.listenForXdebug()
            }

            Divider()

            Menu("Run Configuration") {
                let configurations = runController?.configurations ?? []
                if configurations.isEmpty {
                    Button("No Configurations") {}.disabled(true)
                } else {
                    ForEach(configurations) { configuration in
                        Button(configuration.name) {
                            runController?.run(configuration)
                        }
                    }
                }
            }

            Button("Manage Run Configurations…") {
                openConfigurations()
            }
        }
    }

    /// Opens the workspace settings (which hosts the Run Configurations editor).
    private func openConfigurations() {
        NSApp.sendAction(
            #selector(CodeEditWindowController.openWorkspaceSettings(_:)),
            to: windowController,
            from: nil
        )
    }
}
