//
//  CommandCenterView.swift
//  CodeEdit
//
//  The tabbed Command Center (⌘K).
//

import SwiftUI

struct CommandCenterView: View {
    @ObservedObject var model: CommandCenterViewModel
    let onClose: () -> Void

    @State private var selection = 0
    @State private var lastTapTime = Date.distantPast
    @State private var lastTapDirection = 0
    @State private var jumpModeUntil: Date?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            tabBar
            Divider()
            resultsList
            Divider()
            footer
        }
        .frame(minWidth: 660, minHeight: 420)
        .background(CommandCenterKeyMonitor(onKeyDown: handleKey))
        .onExitCommand { onClose() }
        .onAppear {
            model.scheduleSearch()
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .light))
                .focused($isFieldFocused)
                .onSubmit(activateSelected)
                .onChange(of: model.query) { _, _ in
                    selection = 0
                    model.scheduleSearch()
                }
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var placeholder: String {
        model.category == .all ? "Search files, symbols, commands…" : "Search \(model.category.title)…"
    }

    // MARK: - Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CommandCenterCategory.allCases) { category in
                    tabButton(category)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func tabButton(_ category: CommandCenterCategory) -> some View {
        let isActive = model.category == category
        return Button {
            model.select(category: category)
            selection = 0
            isFieldFocused = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.systemImage).font(.system(size: 12))
                Text(category.title).font(.system(size: 12, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    @ViewBuilder private var resultsList: some View {
        if model.results.isEmpty {
            VStack {
                Spacer()
                Text(model.query.isEmpty ? "Type to search" : "No results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                            if model.category == .all,

                               index == 0 || model.results[index - 1].category != item.category {
                                sectionHeader(item.category)
                            }
                            row(item, isSelected: index == selection)
                                .id(item.id)
                                .onHover { hovering in
                                    if hovering { selection = index }
                                }
                                .onTapGesture {
                                    selection = index
                                    activateSelected()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selection) { _, newValue in
                    guard model.results.indices.contains(newValue) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(model.results[newValue].id, anchor: nil)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ category: CommandCenterCategory) -> some View {
        Text(category.title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func row(_ item: CommandCenterItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                if !item.matchedCharacters.isEmpty {
                    QuickSearchResultLabel(labelName: item.title, charactersToHighlight: item.matchedCharacters)
                        .lineLimit(1)
                } else {
                    Text(item.title).lineLimit(1)
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let accessory = item.accessory {
                Text(accessory)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑", "↓", "move")
            hint("←", "→", "tabs")
            hint("⏎", nil, "select")
            hint("esc", nil, "close")
            Spacer()
            Text("\(model.results.count) results")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func hint(_ key: String, _ key2: String?, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            if let key2 {
                Text(key2).font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func activateSelected() {
        guard model.results.indices.contains(selection) else { return }
        model.activate(model.results[selection])
        onClose()
    }

    /// Handles app-level key events while the Command Center is key. Returns `true` to consume.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: // down
            if selection < model.results.count - 1 { selection += 1 }
            return true
        case 126: // up
            if selection > 0 { selection -= 1 }
            return true
        case 123: // left
            return handleHorizontal(direction: -1)
        case 124: // right
            return handleHorizontal(direction: 1)
        case 36: // return
            activateSelected()
            return true
        case 53: // escape
            onClose()
            return true
        default:
            return false
        }
    }

    /// Switches tabs on ←/→ when the query is empty, the caret is at the edge, or "jump mode" is active
    /// (entered by double-tapping ←/→). Otherwise the field moves the caret as usual.
    private func handleHorizontal(direction: Int) -> Bool {
        let now = Date()
        let isDoubleTap = lastTapDirection == direction && now.timeIntervalSince(lastTapTime) < 0.3
        lastTapDirection = direction
        lastTapTime = now

        let jumpActive = jumpModeUntil.map { now < $0 } ?? false
        guard jumpActive || isDoubleTap || queryEmptyOrCaretAtEdge(direction) else {
            return false
        }

        jumpModeUntil = now.addingTimeInterval(3)
        model.cycleCategory(by: direction)
        selection = 0
        isFieldFocused = true
        return true
    }

    private func queryEmptyOrCaretAtEdge(_ direction: Int) -> Bool {
        let editor = NSApp.keyWindow?.firstResponder as? NSTextView
        let text = editor?.string ?? model.query
        guard !text.isEmpty else { return true }
        let length = (text as NSString).length
        let selected = editor?.selectedRange() ?? NSRange(location: length, length: 0)
        if direction < 0 {
            return selected.location == 0 && selected.length == 0
        }
        return NSMaxRange(selected) == length
    }
}
