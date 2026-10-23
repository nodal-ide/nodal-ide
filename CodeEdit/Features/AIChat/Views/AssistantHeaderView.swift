import AppKit
import SwiftUI

struct AssistantHeaderView: View {
    @ObservedObject var session: AssistantSession
    let onNewChat: () -> Void
    let onClear: () -> Void

    @State private var showingProviderInfo = false
    @State private var showingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Assistant")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)

                Button {
                    showingHistory.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.icon(size: 24))
                .help("Conversation History")
                .accessibilityLabel("Conversation History")
                .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                    AssistantHistoryView(session: session, onNewChat: onNewChat)
                }

                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.icon(size: 24))
                .help("New Chat")
                .accessibilityLabel("New Chat")

                Menu {
                    Button("Copy Transcript") {
                        copyTranscript()
                    }
                    .disabled(session.messages.isEmpty)

                    Divider()

                    Button("Clear Conversation", role: .destructive) {
                        onClear()
                    }
                    .disabled(session.messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Assistant Actions")
                .accessibilityLabel("Assistant Actions")
            }

            Button {
                showingProviderInfo.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(providerText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Provider Information")
            .accessibilityLabel("Provider: \(providerText)")
            .popover(isPresented: $showingProviderInfo, arrowEdge: .bottom) {
                AssistantProviderPopover(provider: session.provider)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var providerText: String {
        guard let provider = session.provider else { return "No provider configured" }
        return "\(provider.name) · \(provider.host)"
    }

    private var statusColor: Color {
        guard let provider = session.provider else { return .orange }
        switch provider.connection {
        case .local, .remote:
            return .green
        case .checking:
            return .yellow
        case .offline, .needsSetup:
            return .orange
        }
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.copyTranscript(), forType: .string)
    }
}

private struct AssistantProviderPopover: View {
    let provider: AssistantProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider?.name ?? "No provider configured")
                        .font(.system(size: 12, weight: .semibold))
                    Text(provider?.connection.label ?? "Needs setup")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let provider {
                Divider()
                LabeledContent("Model") {
                    Text(provider.model)
                }
                LabeledContent("Connection") {
                    Text(provider.connection.label)
                }
                LabeledContent("Destination") {
                    Text(provider.host)
                }
            }

            Text(destinationMessage)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private var destinationMessage: String {
        guard let provider else {
            return "Add a provider in Settings > AI Assistant before sending a message."
        }
        if provider.connection == .local {
            return "Requests go to \(provider.host). This loopback endpoint is local to this Mac."
        }
        return "Requests go to \(provider.host). Workspace context is sent only after you allow it for this provider."
    }
}
