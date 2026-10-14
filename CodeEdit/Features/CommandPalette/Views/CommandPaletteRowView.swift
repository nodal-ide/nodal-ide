//
//  CommandPaletteRowView.swift
//  CodeEdit
//

import SwiftUI

struct CommandPaletteRowView: View {
    let item: PaletteItem

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                if item.kind == .file, !item.matchedCharacters.isEmpty {
                    QuickSearchResultLabel(
                        labelName: item.title,
                        charactersToHighlight: item.matchedCharacters
                    )
                } else {
                    Text(item.title)
                        .lineLimit(1)
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .file:
            if let url = item.fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "doc")
                    .frame(width: 20)
            }
        case .symbol:
            Image(systemName: symbolIcon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
        case .command:
            Image(systemName: "command")
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
    }

    private var symbolIcon: String {
        switch item.symbolKind {
        case .class, .trait, .interface, .enum: return "cube"
        case .function, .method: return "function"
        case .property, .variable: return "square.on.square"
        case .constant: return "number"
        case .namespace: return "folder"
        default: return "list.bullet"
        }
    }
}