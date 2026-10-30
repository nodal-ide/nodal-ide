import SwiftUI

struct XdebugStatusRow: View {
    @ObservedObject
    private var detector = AppServices.xdebugDetector

    @FocusedValue(\.activeWorkspace)
    private var activeWorkspace

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
        .task(id: activeWorkspace?.fileURL) {
            await detector.refresh(workspace: activeWorkspace)
        }
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
        case let .loaded(_, version, mode, workspaceName):
            if let workspaceName {
                return "Xdebug \(version) loaded · mode: \(mode) (\(workspaceName))"
            }
            return "Xdebug \(version) loaded · mode: \(mode)"
        }
    }
}
