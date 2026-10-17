//
//  BreakpointStore.swift
//  CodeEdit
//
//  Persists breakpoints for a workspace (`<workspace>/.codeedit/breakpoints.json`).
//

import Combine
import Foundation

@MainActor
final class BreakpointStore: ObservableObject {
    @Published private(set) var breakpoints: [Breakpoint] = []

    private let fileURL: URL

    init(workspaceURL: URL?) {
        if let workspaceURL {
            fileURL = workspaceURL.appending(path: ".codeedit").appending(path: "breakpoints.json")
        } else {
            fileURL = URL(filePath: "/dev/null")
        }
        load()
    }

    func breakpoints(for url: URL) -> [Breakpoint] {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return breakpoints.filter { $0.filePath == path }
    }

    /// The set of enabled line numbers with a breakpoint in a file.
    func lines(for url: URL) -> Set<Int> {
        Set(breakpoints(for: url).filter(\.enabled).map(\.line))
    }

    /// All breakpoint lines in a file (enabled and disabled).
    func allLines(for url: URL) -> Set<Int> {
        Set(breakpoints(for: url).map(\.line))
    }

    /// Disabled breakpoint lines in a file.
    func disabledLines(for url: URL) -> Set<Int> {
        Set(breakpoints(for: url).filter { !$0.enabled }.map(\.line))
    }

    /// The breakpoint at a line, if any.
    func breakpoint(_ url: URL, line: Int) -> Breakpoint? {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return breakpoints.first { $0.filePath == path && $0.line == line }
    }

    /// Adds a breakpoint if none exists, otherwise toggles its enabled state (Xcode-style gutter click).
    func toggleOrAdd(_ url: URL, line: Int) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if let index = breakpoints.firstIndex(where: { $0.filePath == path && $0.line == line }) {
            breakpoints[index].enabled.toggle()
        } else {
            breakpoints.append(Breakpoint(filePath: path, line: line))
        }
        save()
    }

    /// Adds an enabled breakpoint at a line if one doesn't already exist.
    func add(_ url: URL, line: Int) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard !breakpoints.contains(where: { $0.filePath == path && $0.line == line }) else { return }
        breakpoints.append(Breakpoint(filePath: path, line: line))
        save()
    }

    /// Removes the breakpoint at a line.
    func remove(_ url: URL, line: Int) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        breakpoints.removeAll { $0.filePath == path && $0.line == line }
        save()
    }

    /// Enables/disables the breakpoint at a line.
    func setEnabled(_ url: URL, line: Int, _ enabled: Bool) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard let index = breakpoints.firstIndex(where: { $0.filePath == path && $0.line == line }) else { return }
        breakpoints[index].enabled = enabled
        save()
    }

    func hasBreakpoint(_ url: URL, line: Int) -> Bool {
        breakpoints(for: url).contains { $0.line == line }
    }

    /// Toggles a breakpoint on a line.
    func toggle(_ url: URL, line: Int) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if let index = breakpoints.firstIndex(where: { $0.filePath == path && $0.line == line }) {
            breakpoints.remove(at: index)
        } else {
            breakpoints.append(Breakpoint(filePath: path, line: line))
        }
        save()
    }

    func remove(_ id: UUID) {
        breakpoints.removeAll { $0.id == id }
        save()
    }

    /// Removes every breakpoint.
    func removeAll() {
        breakpoints.removeAll()
        save()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[index].enabled = enabled
        save()
    }

    func setCondition(_ id: UUID, _ condition: String?) {
        guard let index = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[index].condition = (condition?.isEmpty ?? true) ? nil : condition
        save()
    }

    /// Breakpoints grouped by file path (for the debug session).
    func groupedByFile() -> [String: [Breakpoint]] {
        Dictionary(grouping: breakpoints.filter(\.enabled), by: \.filePath)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        breakpoints = (try? JSONDecoder().decode([Breakpoint].self, from: data)) ?? []
    }

    private func save() {
        guard fileURL.path != "/dev/null" else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(breakpoints) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
