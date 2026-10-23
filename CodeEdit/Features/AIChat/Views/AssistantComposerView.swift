import SwiftUI

struct AssistantComposerView: View {
    @ObservedObject var session: AssistantSession

    @State private var editorHeight: CGFloat = 24

    private var characterCount: Int {
        session.draft.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantContextBarView(session: session)

            ZStack(alignment: .topLeading) {
                AssistantComposerTextView(
                    text: $session.draft,
                    height: $editorHeight,
                    isEditable: true,
                    focusRequest: session.focusRequest,
                    onSubmit: session.send
                )
                .frame(height: editorHeight)

                if session.draft.isEmpty {
                    Text("Ask about this code…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 1)
                        .padding(.top, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(session.destinationLabel)
                        Text("·")
                        Text(destinationDetail)
                    }
                    Text(session.destinationLabel)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

                Spacer(minLength: 4)

                if characterCount > AssistantSession.maximumDraftLength - 2_000 {
                    Text("\(characterCount.formatted())/\(AssistantSession.maximumDraftLength.formatted())")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(
                            characterCount >= AssistantSession.maximumDraftLength ? Color.orange : Color.secondary
                        )
                }

                sendButton
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 7)
        .padding(.bottom, 7)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.CornerRadius.large)
                .stroke(Color(nsColor: .separatorColor).opacity(0.9), lineWidth: 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var sendButton: some View {
        Button {
            if session.isStreaming {
                session.stop()
            } else {
                session.send()
            }
        } label: {
            Image(systemName: session.isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: session.isStreaming ? 7.5 : 11, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .background(buttonBackground, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!session.isStreaming && !session.canSend)
        .help(session.isStreaming ? "Stop" : "Send")
        .accessibilityLabel(session.isStreaming ? "Stop" : "Send")
        .accessibilityIdentifier("AssistantSendButton")
    }

    private var destinationDetail: String {
        guard let provider = session.provider else { return "No destination" }
        return provider.id == "mock" ? "No network requests" : "to \(session.destinationHost)"
    }

    private var statusColor: Color {
        session.provider?.isUsable == true ? .green : .orange
    }

    private var buttonBackground: Color {
        if session.isStreaming {
            return Color.secondary.opacity(0.18)
        }
        return session.canSend ? Color.accentColor : Color.secondary.opacity(0.12)
    }

    private var iconColor: Color {
        if session.isStreaming {
            return .primary
        }
        return session.canSend ? .white : Color.secondary.opacity(0.7)
    }
}
