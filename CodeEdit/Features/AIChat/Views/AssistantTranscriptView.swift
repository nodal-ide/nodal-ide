import SwiftUI

struct AssistantTranscriptView: View {
    @ObservedObject var session: AssistantSession

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var isNearBottom = true
    @State private var pendingScroll: Task<Void, Never>?

    private let bottomID = "assistant-transcript-bottom"
    private let coordinateSpace = "assistant-transcript"
    private var displayedMessages: [AssistantMessage] { session.messages.suffix(200).map { $0 } }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // Only render the most recent 200 messages to keep scrolling fast;
                            // the conversation itself is still complete in the model.
                            ForEach(displayedMessages) { message in
                                AssistantMessageView(
                                    message: message,
                                    onRetry: { session.retry(message.id) },
                                    onOpenCitation: { session.openCitation($0) }
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomID)
                                .background {
                                    GeometryReader { marker in
                                        Color.clear.preference(
                                            key: AssistantBottomMarkerKey.self,
                                            value: marker.frame(in: .named(coordinateSpace)).maxY
                                        )
                                    }
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .coordinateSpace(name: coordinateSpace)
                    .onPreferenceChange(AssistantBottomMarkerKey.self) { bottom in
                        let nearBottom = bottom <= geometry.size.height + 40
                        if nearBottom != isNearBottom {
                            isNearBottom = nearBottom
                        }
                    }
                    .onChange(of: session.contentRevision) { _, _ in
                        guard isNearBottom else { return }
                        scrollToBottom(proxy, animated: false)
                    }
                    .onChange(of: session.phase) { _, phase in
                        guard phase.isStreaming, isNearBottom else { return }
                        scrollToBottom(proxy, animated: false)
                    }
                    .onAppear {
                        scrollToBottom(proxy, animated: false)
                    }
                    .onDisappear {
                        pendingScroll?.cancel()
                    }

                    if !isNearBottom {
                        Button {
                            scrollToBottom(proxy, animated: !reduceMotion)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: 26)
                                .background(.regularMaterial, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Jump to latest message")
                        .accessibilityLabel("Jump to latest message")
                        .padding(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isNearBottom)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        pendingScroll?.cancel()
        pendingScroll = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }
}

private struct AssistantBottomMarkerKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
