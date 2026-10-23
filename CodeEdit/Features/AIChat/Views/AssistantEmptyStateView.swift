import SwiftUI

struct AssistantEmptyStateView: View {
    let provider: AssistantProvider?
    let onSuggestion: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.11), in: Circle())

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if provider?.isUsable == true {
                    VStack(spacing: 6) {
                        ForEach(AssistantSuggestion.all) { suggestion in
                            suggestionButton(suggestion)
                        }
                    }
                } else {
                    Label(
                        provider == nil ? "Provider setup is unavailable in this build." : "Check the provider server.",
                        systemImage: provider == nil ? "gearshape" : "wifi.exclamationmark"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium))
                }

                Label("Nothing is sent until you press Send.", systemImage: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    private var title: String {
        guard let provider else { return "Assistant not configured" }
        if !provider.isUsable {
            return "Provider unavailable"
        }
        return "Ask about your code"
    }

    private var message: String {
        guard let provider else {
            return "A provider must be connected before the assistant can respond."
        }
        if !provider.isUsable {
            return "The configured provider is \(provider.connection.label.lowercased()). Reconnect it to continue."
        }
        return "Get help understanding, reviewing, or planning changes in this workspace."
    }

    private func suggestionButton(_ suggestion: AssistantSuggestion) -> some View {
        Button {
            onSuggestion(suggestion.prompt)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: suggestion.systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                Text(suggestion.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds this prompt to the message field")
    }
}

private struct AssistantSuggestion: Identifiable {
    let id: String
    let title: String
    let prompt: String
    let systemImage: String

    static let all = [
        AssistantSuggestion(
            id: "selection",
            title: "Review the current selection",
            prompt: "Review the current selection and suggest improvements.",
            systemImage: "text.cursor"
        ),
        AssistantSuggestion(
            id: "error",
            title: "Explain the current error",
            prompt: "Explain the current error and propose a focused fix.",
            systemImage: "exclamationmark.triangle"
        ),
        AssistantSuggestion(
            id: "feature",
            title: "Plan a feature",
            prompt: "Help me plan a feature for this workspace.",
            systemImage: "list.bullet.clipboard"
        ),
        AssistantSuggestion(
            id: "performance",
            title: "Find a Big-O improvement",
            prompt: "Look for a meaningful Big-O improvement in the current code.",
            systemImage: "speedometer"
        )
    ]
}
