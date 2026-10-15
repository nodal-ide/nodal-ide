//
//  DiffViewerWindow.swift
//  CodeEdit
//

import SwiftUI

/// The diff viewer window scene.
struct DiffViewerWindow: Scene {
    var body: some Scene {
        Window("Diff", id: SceneID.diff.rawValue) {
            DiffViewerView(state: DiffViewerState.shared)
        }
    }
}
