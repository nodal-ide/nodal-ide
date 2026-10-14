//
//  ScratchpadView.swift
//  CodeEdit
//

import SwiftUI

struct ScratchpadView: View {
    @ObservedObject private var store = ScratchpadStore.shared

    var body: some View {
        TextEditor(
            text: Binding(
                get: { store.text },
                set: {
                    store.text = $0
                    store.scheduleSave()
                }
            )
        )
        .font(.system(size: 13, design: .monospaced))
        .padding(6)
        .frame(minWidth: 480, minHeight: 360)
    }
}