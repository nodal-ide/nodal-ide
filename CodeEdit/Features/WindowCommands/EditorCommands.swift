//
//  EditorCommands.swift
//  CodeEdit
//
//  Created by Bogdan Belogurov on 21/05/2025.
//

import SwiftUI
import CodeEditKit

struct EditorCommands: Commands {

    @UpdatingWindowController var windowController: CodeEditWindowController?
    private var editor: Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    var body: some Commands {
        CommandMenu("Editor") {
            Menu("Structure") {
                Button("Move line up") {
                    editor?.selectedTab?.rangeTranslator.moveLinesUp()
                }
                .keyboardShortcut("[", modifiers: [.command, .option])

                Button("Move line down") {
                    editor?.selectedTab?.rangeTranslator.moveLinesDown()
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
            }

            Divider()

            Button("Format Document") {
                LSPEditorActions.formatDocument(workspace: windowController?.workspace)
            }
            .keyboardShortcut("f", modifiers: [.option, .shift])

            Button("Format Selection") {
                LSPEditorActions.formatSelection(workspace: windowController?.workspace)
            }

            Button("Rename Symbol…") {
                LSPEditorActions.renameSymbol(workspace: windowController?.workspace)
            }
            .keyboardShortcut("r", modifiers: [.control, .command])

            Button("Find All References") {
                windowController?.findReferences()
            }

            Button("Code Actions…") {
                editor?.selectedTab?.rangeTranslator.controller?.showCodeActions()
            }
            .keyboardShortcut(".", modifiers: [.command])
        }
    }
}
