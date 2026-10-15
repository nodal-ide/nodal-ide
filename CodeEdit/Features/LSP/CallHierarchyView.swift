//
//  CallHierarchyView.swift
//  CodeEdit
//
//  Shows the call hierarchy as an expandable tree of callers and callees.
//

import SwiftUI
import CodeEditSourceEditor
import LanguageServerProtocol

struct CallHierarchyView: View {
    @ObservedObject var model: CallHierarchyViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 420, minHeight: 320)
        .task {
            await model.prepare()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
            Text("Call Hierarchy")
                .font(.headline)
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if model.isLoading, model.roots.isEmpty {
            Spacer()
            ProgressView("Preparing call hierarchy…")
                .frame(maxWidth: .infinity)
            Spacer()
        } else if model.isEmpty {
            Spacer()
            Text("No call hierarchy available at the cursor.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.roots) { node in
                        CallHierarchyNodeView(node: node, depth: 0)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct CallHierarchyNodeView: View {
    @ObservedObject var node: CallHierarchyNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, indent(depth + 1) + 16)
                    .padding(.vertical, 2)
            }
            if node.expanded {
                section("Callers", nodes: node.incoming, depth: depth + 1)
                section("Callees", nodes: node.outgoing, depth: depth + 1)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            Button {
                node.toggleExpansion()
            } label: {
                Image(systemName: node.expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: Self.icon(for: node.entry.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(node.entry.name)
                .lineLimit(1)

            if let detail = node.entry.detail, !detail.isEmpty {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(locationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
        .padding(.leading, indent(depth))
        .padding(.trailing, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .help(node.entry.detail ?? node.entry.name)
    }

    @ViewBuilder
    private func section(_ title: String, nodes: [CallHierarchyNode]?, depth: Int) -> some View {
        if let nodes, !nodes.isEmpty {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, indent(depth) + 28)
                .padding(.top, 3)
            ForEach(nodes) { child in
                CallHierarchyNodeView(node: child, depth: depth)
            }
        }
    }

    private func indent(_ depth: Int) -> CGFloat {
        CGFloat(depth) * 14 + 8
    }

    private var locationText: String {
        let file = node.entry.fileURL?.lastPathComponent ?? "—"
        return "\(file):\(node.entry.line + 1)"
    }

    private func open() {
        guard let url = node.entry.fileURL else { return }
        let entry = node.entry
        CodeEditDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
            guard let document = document as? CodeFileDocument,
                  let string = document.content?.string else {
                return
            }
            let offset = Self.offset(forLine: entry.line, column: entry.column, in: string as NSString)
            document.openOptions = .init(cursorPositions: [CursorPosition(range: NSRange(location: offset, length: 0))])
        }
    }

    private static func offset(forLine line: Int, column: Int, in text: NSString) -> Int {
        var currentLine = 0
        var index = 0
        while index < text.length, currentLine < line {
            if text.character(at: index) == 0x0A {
                currentLine += 1
            }
            index += 1
        }
        return min(index + column, text.length)
    }

    private static func icon(for kind: SymbolKind?) -> String {
        switch kind {
        case .class, .enum, .interface, .namespace, .module:
            return "cube"
        case .method, .function, .constructor:
            return "function"
        case .property, .field, .variable:
            return "square.on.square"
        case .constant:
            return "number"
        default:
            return "function"
        }
    }
}
