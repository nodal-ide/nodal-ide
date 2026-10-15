//
//  RuntimeManagerWindow.swift
//  CodeEdit
//
//  The Runtime Manager window scene.
//

import SwiftUI

struct RuntimeManagerWindow: Scene {
    var body: some Scene {
        Window("Runtimes", id: SceneID.runtimes.rawValue) {
            RuntimeManagerView()
        }
    }
}
