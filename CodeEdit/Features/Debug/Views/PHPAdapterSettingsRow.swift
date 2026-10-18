//
//  PHPAdapterSettingsRow.swift
//  CodeEdit
//
//  Developer settings row: detect/install the PHP debug adapter.
//

import SwiftUI

struct PHPAdapterSettingsRow: View {
    @ObservedObject private var installer = AppServices.phpAdapterInstaller

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PHP Debug Adapter")
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            trailing
        }
        .task { installer.refresh() }
    }

    private var trailing: some View {
        Group {
            switch installer.status {
            case .installing:
                ProgressView().controlSize(.small)
            case .installed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Reinstall") { Task { await installer.install() } }
            default:
                Button("Install") { Task { await installer.install() } }
            }
        }
    }

    private var statusText: String {
        switch installer.status {
        case .installed(let path): return "Installed · \(path)"
        case .installing: return "Installing vscode-php-debug…"
        case .failed(let message): return "Failed: \(message)"
        case .notInstalled: return "Not installed — installs vscode-php-debug (requires Node.js)."
        case .unknown: return "Checking…"
        }
    }
}
