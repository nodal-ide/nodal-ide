//
//  ThemeFilePanels.swift
//  CodeEdit
//
//  Presents the open/save panels for importing and exporting themes and forwards the chosen URLs to
//  `ThemeModel`. Keeps `NSOpenPanel`/`NSSavePanel` out of the model.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum ThemeFilePanels {
    static func importTheme(into model: ThemeModel) {
        let panel = NSOpenPanel()
        panel.prompt = "Import"
        panel.allowedContentTypes = [UTType(filenameExtension: "cetheme")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { result in
            if result == .OK, let url = panel.urls.first {
                model.duplicate(url)
            }
        }
    }

    static func export(_ theme: Theme, from model: ThemeModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cetheme")!]
        panel.nameFieldStringValue = theme.displayName
        panel.prompt = "Export"
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let destinationURL = panel.url {
                model.export(theme, to: destinationURL)
            }
        }
    }

    static func exportAllCustomThemes(from model: ThemeModel) {
        let panel = NSOpenPanel()
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { result in
            if result == .OK, let directory = panel.url {
                model.exportAllCustomThemes(to: directory)
            }
        }
    }
}
