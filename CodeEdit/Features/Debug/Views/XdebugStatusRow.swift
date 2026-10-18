//
//  XdebugStatusRow.swift
//  CodeEdit
//
//  Developer settings row: Xdebug detection + install guidance.
//

import SwiftUI

struct XdebugStatusRow: View {
    @ObservedObject private var detector = AppServices.xdebugDetector

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Xdebug")
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            trailing
        }
        .task { await detector.refresh() }
    }

    private var trailing: some View {
        Group {
            switch detector.status {
            case .checking:
                ProgressView().controlSize(.small)
            case .notInstalled:
                Button("Install Guide") {
                    if let url = URL(string: "https://xdebug.org/docs/install") {
                        NSWorkspace.shared.open(url)
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private var statusText: String {
        switch detector.status {
        case .unknown: return "Checking…"
        case .checking: return "Checking…"
        case .noPHP: return "No PHP runtime found."
        case .notInstalled(let php):
            return "Not loaded for \(php). Install with `pecl install xdebug` (or Homebrew), then restart PHP."
        case let .loaded(_, version, mode):
            return "Xdebug \(version) loaded · mode: \(mode)"
        }
    }
}
