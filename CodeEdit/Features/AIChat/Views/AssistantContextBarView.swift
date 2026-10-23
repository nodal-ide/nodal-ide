import AppKit
import SwiftUI

struct AssistantContextBarView: View {
    @ObservedObject var session: AssistantSession

    @State private var showingPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                addMenu

                if session.contextItems.isEmpty {
                    Text("Add context")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(session.contextItems) { item in
                                contextChip(item)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Preview context")
                .accessibilityLabel("Preview context")
                .accessibilityIdentifier("AssistantPreviewContextButton")
            }

            if session.selectionNeedsRefresh {
                Button {
                    session.refreshSelection()
                } label: {
                    Label("Selection changed — refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .help("Replace the attached selection with the current one")
            }
        }
        .sheet(isPresented: $showingPreview) {
            AssistantContextPreviewView(
                preview: session.contextPreview,
                destination: session.destinationHost
            )
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Current Selection") {
                session.addCurrentSelectionOrActiveFile()
            }
            Button("Active File") {
                session.addActiveFile()
            }
            Button("Open Files") {
                session.addOpenFiles()
            }
            Button("Diagnostics") {
                session.addDiagnostics()
            }
            Button("Tasks") {
                session.addTasks()
            }
            if session.hasContextItems {
                Divider()
                Button("Clear Context") {
                    session.clearContext()
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Color.secondary.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add context")
        .accessibilityLabel("Add context")
        .accessibilityIdentifier("AssistantAddContextButton")
    }

    private func contextChip(_ item: AssistantContextItem) -> some View {
        HStack(spacing: 3) {
            Image(systemName: item.isSensitive ? "lock.fill" : item.kind.symbolName)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(item.isSensitive || !item.warnings.isEmpty ? Color.orange : Color.secondary)

            Text(item.title)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if item.isTruncated {
                Image(systemName: "ellipsis")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Button {
                session.removeContextItem(id: item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove \(item.title)")
            .accessibilityLabel("Remove \(item.title)")
        }
        .padding(.leading, 5)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .background(
            (item.isSensitive ? Color.orange : Color.accentColor).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    (item.isSensitive ? Color.orange : Color.accentColor).opacity(0.22),
                    lineWidth: 0.5
                )
        }
        .help(tooltip(for: item))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.label): \(item.title)")
    }

    private func tooltip(for item: AssistantContextItem) -> String {
        var lines = [item.title]
        if let relativePath = item.relativePath {
            lines.append(relativePath)
        }
        if !item.warnings.isEmpty {
            lines.append(contentsOf: item.warnings)
        }
        return lines.joined(separator: "\n")
    }
}

struct AssistantContextPreviewView: View {
    let preview: AssistantContextPreview
    let destination: String

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Context Preview")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Destination: \(destination)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("~\(preview.estimatedTokens.formatted()) tokens")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            if !preview.warnings.isEmpty || !preview.omittedTitles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !preview.omittedTitles.isEmpty {
                        Text("Not included: \(preview.omittedTitles.joined(separator: ", "))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))

                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("System instructions", text: preview.systemInstructions)
                    section("Context to send", text: preview.contextText)
                }
                .padding(14)
            }

            Divider()

            HStack {
                Text("Nothing is sent until you press Send.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(fullText, forType: .string)
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 540)
    }

    private var fullText: String {
        """
        SYSTEM INSTRUCTIONS
        \(preview.systemInstructions)

        CONTEXT TO SEND
        \(preview.contextText)
        """
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
