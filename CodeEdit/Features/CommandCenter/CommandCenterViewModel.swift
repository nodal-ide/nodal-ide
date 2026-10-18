//
//  CommandCenterViewModel.swift
//  CodeEdit
//
//  Backs the tabbed Command Center.
//

import Combine
import Foundation

@MainActor
final class CommandCenterViewModel: ObservableObject {
    @Published var query = ""
    @Published var category: CommandCenterCategory = .all
    @Published var results: [CommandCenterItem] = []
    @Published var isSearching = false

    let workspace: WorkspaceDocument
    private var task: Task<Void, Never>?

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
        CommandCenterProviders.register(for: workspace)
    }

    func reset() {
        query = ""
        category = .all
        results = []
        task?.cancel()
    }

    /// Debounced search of the active category.
    func scheduleSearch() {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let category = self.category
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.isSearching = true
            let items = await AppServices.commandCenterRegistry.search(trimmed, category: category)
            guard !Task.isCancelled else { return }
            self.results = items
            self.isSearching = false
        }
    }

    func select(category: CommandCenterCategory) {
        guard category != self.category else { return }
        self.category = category
        scheduleSearch()
    }

    func cycleCategory(by delta: Int) {
        let categories = CommandCenterCategory.allCases
        guard let index = categories.firstIndex(of: category) else { return }
        let next = (index + delta + categories.count) % categories.count
        select(category: categories[next])
    }

    func activate(_ item: CommandCenterItem) {
        CommandCenterRouter.activate(item, workspace: workspace)
    }
}
