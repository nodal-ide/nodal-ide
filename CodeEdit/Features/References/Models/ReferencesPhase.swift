import Foundation
import CodeEditLang

enum ReferencesPhase: Equatable {
    case idle
    case searching
    case results
    case unsupported(String)
    case failed(ReferenceQueryError)

    var isSearching: Bool {
        if case .searching = self { return true }
        return false
    }
}
