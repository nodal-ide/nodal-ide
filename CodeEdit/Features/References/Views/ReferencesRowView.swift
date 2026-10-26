import SwiftUI
import CodeEditLang

struct ReferencesRowView: View {
    let reference: EditorReference
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
                .frame(width: 12, alignment: .leading)
            Text(reference.preview.isEmpty ? " " : reference.preview)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(reference.kind == .declaration ? .primary : .secondary)
            Spacer(minLength: 4)
            Text("\(reference.line):\(reference.column)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .help("\(reference.container.map { "\($0) · " } ?? "")Line \(reference.line), column \(reference.column)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = ["Line \(reference.line), column \(reference.column)"]
        if reference.kind == .declaration { parts.append("declaration") }
        if reference.isHeuristic { parts.append("name match") }
        parts.append(reference.preview)
        return parts.joined(separator: ", ")
    }

    private var icon: String {
        if reference.isHeuristic { return "text.magnifyingglass" }
        switch reference.kind {
        case .declaration: return "pin.fill"
        case .write: return "pencil"
        case .read: return "arrow.turn.down.right"
        case .text: return "text.magnifyingglass"
        }
    }

    private var tint: Color {
        if reference.isHeuristic { return .secondary }
        switch reference.kind {
        case .declaration: return .accentColor
        case .write: return .orange
        case .read, .text: return .secondary
        }
    }
}

struct ReferencesFileHeaderView: View {
    let group: ReferenceFileGroup
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 8)
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(group.displayPath)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(group.count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .help(group.fileURL.path(percentEncoded: false))
        .accessibilityLabel("\(group.displayPath), \(group.count) references")
    }
}

struct ReferencesHeuristicHeaderView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 9))
            Text("Name matches (receiver type unknown)")
                .font(.system(size: 9))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 9).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .help("Occurrences that use the same name; the receiver's type can't be resolved statically.")
    }
}

extension ReferenceTarget.Kind {
    var systemImage: String {
        switch self {
        case .type: return "shippingbox"
        case .function, .method: return "function"
        case .property: return "p.square"
        case .constant: return "k.square"
        case .variable: return "v.square"
        case .unknown: return "textformat.abc"
        }
    }
}
