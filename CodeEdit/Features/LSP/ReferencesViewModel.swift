//
//  ReferencesViewModel.swift
//  CodeEdit
//
//  Backs the Find References results panel.
//

import Combine
import Foundation

@MainActor
final class ReferencesViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [PaletteItem] = []

    private let allItems: [PaletteItem]

    init(items: [PaletteItem]) {
        self.allItems = items
        self.results = items
    }

    func filter() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = allItems
            return
        }
        results = allItems.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}
