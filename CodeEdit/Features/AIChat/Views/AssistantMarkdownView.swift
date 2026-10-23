import SwiftUI

struct AssistantMarkdownView: View {
    let content: String
    var citations: [AssistantCitation] = []
    var isStreaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(
                Array(
                    AssistantMarkdownParser.parse(displayContent).enumerated()
                ),
                id: \.offset
            ) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayContent: String {
        AssistantCitationParser.removingKnownCitations(from: content, citations: citations)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 2 : 0)
                .textSelection(.enabled)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .bulletList(let items):
            list(items, marker: "•")
        case .numberedList(let items):
            numberedList(items)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 2)
                Text(inline(text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case let .code(language, content):
            AssistantCodeBlockView(language: language, content: content, isStreaming: isStreaming)
        case .divider:
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.vertical, 2)
        case let .table(headers, rows):
            table(headers: headers, rows: rows)
        }
    }

    private func list(_ items: [String], marker: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(marker)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 9, alignment: .trailing)
                    Text(inline(item))
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func numberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(index + 1).")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(inline(item))
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func table(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(inline(header))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                    .gridCellColumns(max(1, headers.count))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell))
                                .font(.system(size: 11.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(9)
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.CornerRadius.medium)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:
            return 16
        case 2:
            return 14.5
        case 3:
            return 13.5
        default:
            return 12.5
        }
    }

    private func inline(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
