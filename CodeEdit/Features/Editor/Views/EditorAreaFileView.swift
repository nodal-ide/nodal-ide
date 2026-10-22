//
//  EditorAreaFileView.swift
//  CodeEdit
//
//  Created by Pavel Kasila on 20.03.22.
//

import AppKit
import AVKit
import CodeEditLanguages
import CodeEditSourceEditor
import Combine
import SwiftUI

struct EditorAreaFileView: View {

    @EnvironmentObject private var editorManager: EditorManager
    @EnvironmentObject private var editor: Editor
    @EnvironmentObject private var statusBarViewModel: StatusBarViewModel

    @Environment(\.edgeInsets)
    private var edgeInsets

    var editorInstance: EditorInstance
    @ObservedObject var codeFile: CodeFileDocument

    @State private var languageExtensionRevision = 0

    @MainActor @ViewBuilder var editorAreaFileView: some View {
        if let utType = codeFile.utType, utType.conforms(to: .text) {
            // Include the language fingerprint so the editor rebuilds when the detected/overridden
            // language changes, and the extension revision so it rebuilds when packs change.
            let catalog = codeFile.workspaceLanguageCatalog()
            CodeFileView(
                editorInstance: editorInstance,
                codeFile: codeFile
            )
            .id(
                "\(ObjectIdentifier(codeFile))-" +
                "\(codeFile.getLanguage(catalog: catalog).fingerprint.rawValue)-" +
                "\(languageExtensionRevision)"
            )
        } else {
            NonTextFileView(fileDocument: codeFile)
                .padding(.top, edgeInsets.top - 1.74)
                .padding(.bottom, StatusBarView.height + 1.26)
                .modifier(UpdateStatusBarInfo(with: codeFile.fileURL))
                .onDisappear {
                    statusBarViewModel.dimensions = nil
                    statusBarViewModel.fileSize = nil
                }
        }
    }

    var body: some View {
        editorAreaFileView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: LanguageExtensionManager.didChangeNotification)) { _ in
                languageExtensionRevision &+= 1
            }
    }
}
