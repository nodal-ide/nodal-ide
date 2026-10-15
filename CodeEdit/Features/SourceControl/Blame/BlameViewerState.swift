//
//  BlameViewerState.swift
//  CodeEdit
//
//  Shared state for the blame window.
//

import Combine
import Foundation

@MainActor
final class BlameViewerState: ObservableObject {
    static let shared = BlameViewerState()

    @Published var fileURL: URL?
    @Published var lines: [BlameLine] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    func load(url: URL, manager: SourceControlManager) {
        self.fileURL = url
        self.lines = []
        self.errorMessage = nil
        self.isLoading = true

        Task {
            let blame = await manager.fileBlame(for: url)
            self.lines = blame ?? []
            if blame == nil {
                self.errorMessage = "Could not load blame for this file (is it tracked by git?)."
            }
            self.isLoading = false
        }
    }
}
