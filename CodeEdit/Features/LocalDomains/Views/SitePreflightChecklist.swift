import SwiftUI

/// Checklist shown above the Local Domain settings. Each dependency is ready, needs an action, or is
/// intentionally skipped; actions install or trust the missing piece without leaving the page.
struct SitePreflightChecklist: View {
    @ObservedObject var model: SitePreflightViewModel
    let site: LocalSiteSettings

    @Environment(\.openWindow)
    private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.items) { item in
                row(item)
            }
            if model.needsHomebrew {
                Label("Homebrew is required to install nginx and mkcert.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ item: SitePreflightItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol(for: item.status))
                .foregroundStyle(color(for: item.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.kind.title)
                    .font(.callout.weight(.medium))
                Text(detail(for: item.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action(for: item)
        }
    }

    @ViewBuilder
    private func action(for item: SitePreflightItem) -> some View {
        if item.status.isActionRequired {
            switch item.kind {
            case .nginx, .mkcert:
                Button(buttonTitle(item)) {
                    Task { await model.install(item.kind, site: site) }
                }
                .disabled(model.isBusy || !model.brewAvailable)
                .help(model.brewAvailable ? "Install with Homebrew." : "Install Homebrew first (brew.sh).")
                .controlSize(.small)
            case .certificate:
                Button(buttonTitle(item)) {
                    Task { await model.install(.certificate, site: site) }
                }
                .disabled(model.isBusy || !model.mkcertInstalled)
                .help(model.mkcertInstalled
                      ? "Trust the CodeEdit CA; macOS asks for your password."
                      : "Install mkcert first.")
                .controlSize(.small)
            case .phpFPM:
                Button("Manage Runtimes…") {
                    openWindow(sceneID: .runtimes)
                }
                .controlSize(.small)
            }
        }
    }

    private func buttonTitle(_ item: SitePreflightItem) -> String {
        guard model.busyKind == item.kind else {
            return item.kind == .certificate ? "Trust" : "Install"
        }
        return item.kind == .certificate ? "Trusting…" : "Installing…"
    }

    private func symbol(for status: SitePreflightStatus) -> String {
        switch status {
        case .checking: return "clock"
        case .ready: return "checkmark.circle.fill"
        case .actionRequired: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func color(for status: SitePreflightStatus) -> Color {
        switch status {
        case .checking, .skipped: return .secondary
        case .ready: return .green
        case .actionRequired: return .orange
        }
    }

    private func detail(for status: SitePreflightStatus) -> String {
        switch status {
        case .checking: return "Checking…"
        case .ready(let detail), .actionRequired(let detail), .skipped(let detail): return detail
        }
    }
}
