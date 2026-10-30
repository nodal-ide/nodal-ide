import Foundation

extension Theme: FuzzySearchable {
    var searchableString: String {
        [displayName, author, id].joined(separator: "\n")
    }
}
