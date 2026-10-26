import Foundation
import CodeEditLang

struct ReferencesFilter: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case project = "Project"
        case currentFile = "Current File"

        var id: String { rawValue }
    }

    var query: String = ""
    var scope: Scope = .project

    func groups(from groups: [ReferenceFileGroup], currentFile: URL?) -> [ReferenceFileGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let current = currentFile?.standardizedFileURL

        var result = groups.compactMap { group -> ReferenceFileGroup? in
            if scope == .currentFile, group.fileURL.standardizedFileURL != current {
                return nil
            }
            let references = trimmed.isEmpty
                ? group.references
                : group.references.filter { matches($0, query: trimmed, path: group.displayPath) }
            guard !references.isEmpty else { return nil }
            return ReferenceFileGroup(
                fileURL: group.fileURL,
                displayPath: group.displayPath,
                references: references
            )
        }

        if let current,
           let index = result.firstIndex(where: { $0.fileURL.standardizedFileURL == current }),
           index > 0 {
            result.insert(result.remove(at: index), at: 0)
        }
        return result
    }

    private func matches(_ reference: EditorReference, query: String, path: String) -> Bool {
        reference.preview.localizedCaseInsensitiveContains(query)
            || (reference.container?.localizedCaseInsensitiveContains(query) ?? false)
            || path.localizedCaseInsensitiveContains(query)
    }
}
