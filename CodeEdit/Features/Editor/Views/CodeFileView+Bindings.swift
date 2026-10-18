//
//  CodeFileView+Bindings.swift
//  CodeEdit
//
//  Editor state binding and breakpoint actions, kept out of the view body.
//

import AppKit
import SwiftUI
import CodeEditSourceEditor

extension CodeFileView {
    /// The editor state binding (cursor, scroll, find/replace).
    var editorStateBinding: Binding<SourceEditorState> {
        Binding(
            get: {
                SourceEditorState(
                    cursorPositions: editorInstance.cursorPositions,
                    scrollPosition: editorInstance.scrollPosition,
                    findText: editorFindText,
                    replaceText: editorReplaceText
                )
            },
            set: { newState in
                editorInstance.cursorPositions = newState.cursorPositions ?? []
                editorInstance.scrollPosition = newState.scrollPosition
                editorInstance.findText = newState.findText
                editorInstance.findTextSubject.send(newState.findText)
                editorInstance.replaceText = newState.replaceText
                editorInstance.replaceTextSubject.send(newState.replaceText)
            }
        )
    }

    /// Adds or toggles a breakpoint on `line` in this file.
    func toggleBreakpoint(line: Int) {
        guard let store = codeFile.findWorkspace()?.breakpointStore, let url = codeFile.fileURL else {
            return
        }
        store.toggleOrAdd(url, line: line)
    }

    /// The context menu for a breakpoint gutter click, when a breakpoint store exists.
    func breakpointMenu(line: Int) -> NSMenu? {
        guard let store = codeFile.findWorkspace()?.breakpointStore, let url = codeFile.fileURL else {
            return nil
        }
        return BreakpointMenu.menu(for: url, line: line, store: store)
    }
}
