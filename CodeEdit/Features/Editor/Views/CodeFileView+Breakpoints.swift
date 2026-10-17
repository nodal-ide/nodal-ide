//
//  CodeFileView+Breakpoints.swift
//  CodeEdit
//
//  Gutter breakpoint + debug-line state for the editor.
//

import Combine
import SwiftUI

extension CodeFileView {
    /// The gutter breakpoint markers for the current file, recomputed on every render.
    var currentBreakpointLines: Set<Int> {
        _ = breakpointRevision
        guard let store = codeFile.findWorkspace()?.breakpointStore, let url = codeFile.fileURL else {
            return []
        }
        return store.allLines(for: url)
    }

    /// The disabled breakpoint lines for the current file.
    var currentDisabledBreakpointLines: Set<Int> {
        _ = breakpointRevision
        guard let store = codeFile.findWorkspace()?.breakpointStore, let url = codeFile.fileURL else {
            return []
        }
        return store.disabledLines(for: url)
    }

    /// The current debug stop line, when the stop is in this file.
    var currentDebugLine: Int? {
        _ = debugRevision
        guard let session = codeFile.findWorkspace()?.debugController?.session,
              session.state.isStopped,
              let frame = session.currentFrame,
              let path = frame.source?.path,
              path == codeFile.fileURL?.path(percentEncoded: false) else {
            return nil
        }
        return frame.line
    }

    /// Find/replace text, which does need to re-render the editor when the find navigator changes it.
    var editorFindText: String? {
        _ = findRevision
        return editorInstance.findText
    }

    var editorReplaceText: String? {
        _ = findRevision
        return editorInstance.replaceText
    }

    /// Whether the document is small enough for the minimap (it maintains a second layout manager).
    var isSmallDocument: Bool {
        (codeFile.content?.length ?? 0) < Metrics.Performance.largeFileCharacterCount
    }

    /// Re-derives the gutter/find state when the breakpoint store, debug session or find text changes.
    func observeEditorState() {
        breakpointObservers.removeAll()
        if let store = codeFile.findWorkspace()?.breakpointStore {
            store.$breakpoints
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { _ in breakpointRevision &+= 1 }
                .store(in: &breakpointObservers)
        }
        if let session = codeFile.findWorkspace()?.debugController?.session {
            session.objectWillChange
                .receive(on: RunLoop.main)
                .sink { _ in debugRevision &+= 1 }
                .store(in: &breakpointObservers)
        }
        // Cursor positions are intentionally NOT observed (they change on every keystroke); only find
        // text needs to re-render the editor.
        editorInstance.$findText
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in findRevision &+= 1 }
            .store(in: &breakpointObservers)
        editorInstance.$replaceText
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in findRevision &+= 1 }
            .store(in: &breakpointObservers)
    }
}
