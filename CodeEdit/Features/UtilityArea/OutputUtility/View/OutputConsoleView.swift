//
//  OutputConsoleView.swift
//  CodeEdit
//
//  A reusable, auto-scrolling, selectable monospaced console line list shared by output/console panes.
//

import SwiftUI

struct OutputConsoleView: View {
    let lines: [String]
    var font: Font = .system(size: 12, design: .monospaced)
    var lineSpacing: CGFloat = 1
    var contentPadding: CGFloat = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: lineSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(font)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(contentPadding)
            }
            .onChange(of: lines.count) { _, _ in
                guard !lines.isEmpty else { return }
                withAnimation { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
            }
        }
    }
}
