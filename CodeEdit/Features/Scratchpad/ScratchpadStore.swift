//
//  ScratchpadStore.swift
//  CodeEdit
//
//  Persistent scratchpad content, stored in Application Support.
//

import Foundation

@MainActor
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()

    @Published var text: String

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent("CodeEdit", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("scratchpad.txt")

        self.fileURL = url
        self.text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Schedules a debounced save.
    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func save() {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}