//
//  ReferencesView.swift
//  CodeEdit
//
//  LSP-backed find-references results panel.
//

import AppKit
import SwiftUI
import CodeEditLang
import CodeEditSourceEditor
import CodeEditLanguages

struct ReferencesView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @ObservedObject var session: ReferencesSession

    var body: some View {
        NavigationStack {
            ReferencesNavigatorView()
        }
    }
}
