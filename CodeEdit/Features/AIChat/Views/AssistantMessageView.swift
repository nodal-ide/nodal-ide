import AppKit
import SwiftUI

struct AssistantMessageView: View {
    let message: AssistantMessage
    let onRetry: () -> Void

    @State private var copied = false

    var body: some View {
        if message.isUser {
            userMessage
        } else {
            assistantMessage
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 36)
            Text(message.content)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.large))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.CornerRadius.large)
                        .stroke(Color.accentColor.opacity(0.16), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You said: \(message.content)")
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 9) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                if !message.content.isEmpty {
                    AssistantMarkdownView(content: message.content)
                }

                if message.status == .streaming {
                    AssistantStreamingStatus(label: message.content.isEmpty ? "Thinking…" : "Writing…")
                } else if message.status == .stopped {
                    Label("Stopped", systemImage: "stop.circle")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if message.status == .failed, let error = message.errorMessage {
                    failureCard(error)
                }

                if !message.content.isEmpty {
                    copyBar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant response")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.13))
            Image(systemName: "sparkles")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var copyBar: some View {
        HStack(spacing: 8) {
            Button {
                copy(message.content)
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10.5))
                    .foregroundStyle(copied ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy response")
            .accessibilityLabel("Copy response")
            Spacer()
        }
    }

    private func failureCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Response failed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.orange)
            Text(error)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button("Retry") {
                    onRetry()
                }
                .controlSize(.small)

                Button("Copy Details") {
                    copy([message.content, error].filter { !$0.isEmpty }.joined(separator: "\n\n"))
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

struct AssistantStreamingStatus: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Assistant is responding")
    }
}
