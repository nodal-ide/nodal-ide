//
//  EditorCommands.swift
//  CodeEdit
//
//  Created by Bogdan Belogurov on 21/05/2025.
//

import AppKit
import SwiftUI
import CodeEditKit

struct EditorCommands: Commands {

    @UpdatingWindowController var windowController: CodeEditWindowController?
    private var editor: Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    private func surround(open: String, close: String) {
        editor?.selectedTab?.rangeTranslator.controller?.surroundSelection(open: open, close: close)
    }

    private func promptSurroundTag() {
        let alert = NSAlert()
        alert.messageText = "Surround with Tag"
        alert.informativeText = "Enter a tag name (e.g. div, span)."
        alert.addButton(withTitle: "Surround")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if input.contains("<") {
            let name = input.trimmingCharacters(in: CharacterSet(charactersIn: "< >"))
                .split(separator: " ").first.map(String.init) ?? input
            surround(open: input, close: "</\(name)>")
        } else {
            surround(open: "<\(input)>", close: "</\(input)>")
        }
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

            Menu("Emmet") {
                Button("Expand Abbreviation") {
                    editor?.selectedTab?.rangeTranslator.controller?.expandEmmetAbbreviation()
                }
            }

            Menu("Surround With") {
                Button("Brackets  ( )") { surround(open: "(", close: ")") }
                Button("Braces  { }") { surround(open: "{", close: "}") }
                Button("Square Brackets  [ ]") { surround(open: "[", close: "]") }
                Button("Double Quotes  \" \"") { surround(open: "\"", close: "\"") }
                Button("Single Quotes  ' '") { surround(open: "'", close: "'") }
                Divider()
                Button("Tag…") { promptSurroundTag() }
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

            Button("Ask Assistant About Selection") {
                windowController?.askAssistantAboutSelection()
            }
            .keyboardShortcut("a", modifiers: [.control, .command])

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
            .keyboardShortcut(KeyEquivalent("\u{F70D}"), modifiers: [.shift])
            .disabled(windowController?.workspace == nil)

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
