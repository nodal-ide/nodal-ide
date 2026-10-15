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

            Button("Stop", systemImage: "stop.fill") {
                runController?.stop()
            }
            .disabled(!(runController?.isRunning ?? false))

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

    /// Opens the workspace's `launch.json` (creating an empty one if needed).
    private func openConfigurations() {
        guard let url = windowController?.workspace?.runConfigurationStore?.launchFileURL,
              url.path != "/dev/null" else {
            return
        }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? "[]".write(to: url, atomically: true, encoding: .utf8)
        }
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true,
            completionHandler: { _, _, _ in }
        )
    }
}
