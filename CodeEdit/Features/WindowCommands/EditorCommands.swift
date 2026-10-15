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

            Menu("Multi-cursor") {
                Button("Select Next Occurrence") {
                    editor?.selectedTab?.rangeTranslator.controller?.textView.selectNextOccurrence()
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Select All Occurrences") {
                    editor?.selectedTab?.rangeTranslator.controller?.textView.selectAllOccurrences()
                }
                .keyboardShortcut("g", modifiers: [.control, .command])

                Divider()

                Button("Add Cursor Above") {
                    editor?.selectedTab?.rangeTranslator.controller?.textView.addCursorAbove()
                }
                .keyboardShortcut(.upArrow, modifiers: [.control, .option])

                Button("Add Cursor Below") {
                    editor?.selectedTab?.rangeTranslator.controller?.textView.addCursorBelow()
                }
                .keyboardShortcut(.downArrow, modifiers: [.control, .option])
            }

            Menu("Folding") {
                Button("Fold All") {
                    editor?.selectedTab?.rangeTranslator.controller?.foldAll()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("Unfold All") {
                    editor?.selectedTab?.rangeTranslator.controller?.unfoldAll()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }

            Divider()

            Button("Format Document") {
                LSPEditorActions.formatDocument(workspace: windowController?.workspace)
            }
            .keyboardShortcut("f", modifiers: [.option, .shift])

            Button("Format Selection") {
                LSPEditorActions.formatSelection(workspace: windowController?.workspace)
            }

            Button("Organize Imports") {
                LSPEditorActions.organizeImports(workspace: windowController?.workspace)
            }

            Button("Rename Symbol…") {
                LSPEditorActions.renameSymbol(workspace: windowController?.workspace)
            }
            .keyboardShortcut("r", modifiers: [.control, .command])

            Button("Find All References") {
                windowController?.findReferences()
            }

            Button("Show Call Hierarchy") {
                windowController?.showCallHierarchy()
            }

            Button("Code Actions…") {
                editor?.selectedTab?.rangeTranslator.controller?.showCodeActions()
            }
            .keyboardShortcut(".", modifiers: [.command])
        }
    }
}
