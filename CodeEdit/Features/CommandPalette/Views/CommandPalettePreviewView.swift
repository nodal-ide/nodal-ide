//
//  CommandPalettePreviewView.swift
//  CodeEdit
//

import SwiftUI

struct CommandPalettePreviewView: View {
    let item: PaletteItem

    var body: some View {
        switch item.kind {
        case .file:
            if let url = item.fileURL {
                OpenQuicklyPreviewView(item: CEWorkspaceFile(url: url))
            } else {
                detail
            }
        default:
            detail
        }
    }

    private var detail: some View {
        VStack(spacing: 8) {
            Image(systemName: item.kind == .command ? "command" : "cube")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.headline)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}