//
//  KnowledgeWindow.swift
//  CodeEdit
//

import SwiftUI

/// The Knowledge Base window scene.
struct KnowledgeWindow: Scene {
    @StateObject private var model = KnowledgeViewModel()

    var body: some Scene {
        Window("Knowledge", id: SceneID.knowledge.rawValue) {
            KnowledgeView(model: model)
                .themeScope()
        }
    }
}
