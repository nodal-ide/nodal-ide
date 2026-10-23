import AppKit
import SwiftUI

struct AssistantCodeBlockView: View {
    let language: String?
    let content: String
    var isStreaming = false

    @ObservedObject private var themeModel: ThemeModel = AppServices.themeModel
    @State private var copied = false
    @State private var highlighted: AttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 6)
                Button {
                    copy()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(copied ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy code")
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted ?? AttributedString(content))
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: highlightRequest) {
            highlighted = nil
            guard !isStreaming,
                  let codeLanguage = AssistantCodeSyntaxHighlighter.language(for: language),
                  let theme = themeModel.selectedTheme?.editor.editorTheme
            else { return }
            highlighted = AssistantCodeSyntaxHighlighter.highlight(
                content,
                language: codeLanguage,
                theme: theme,
                font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            )
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 0.5)
        }
    }

    private var highlightRequest: HighlightRequest {
        HighlightRequest(
            content: content,
            language: language,
            themeName: themeModel.selectedTheme?.name ?? "",
            isStreaming: isStreaming
        )
    }

    private var label: String {
        guard let language, !language.isEmpty else { return "Code" }
        return language
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

private struct HighlightRequest: Equatable {
    let content: String
    let language: String?
    let themeName: String
    let isStreaming: Bool
}
