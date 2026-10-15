//
//  RuntimeToolingBanner.swift
//  CodeEdit
//
//  A warning banner shown when required tooling (Homebrew) is missing.
//

import SwiftUI

struct RuntimeToolingBanner: View {
    @ObservedObject var tooling: RuntimeTooling

    var body: some View {
        if case .missing = tooling.brew {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Homebrew is required to install PHP runtimes.")
                        .font(.callout)
                    Text("Node.js installs don't need it. Install Homebrew, then refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Get Homebrew") {
                    tooling.openHomebrewInstallPage()
                }
                Button {
                    Task { await tooling.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check tooling")
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        if !tooling.hasNetwork {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text("No network connection — runtimes can't be downloaded.")
                    .font(.callout)
                Spacer(minLength: 8)
                Button {
                    Task { await tooling.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check")
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
