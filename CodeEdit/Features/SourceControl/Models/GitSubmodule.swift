import Foundation

struct GitSubmodule: Hashable, Sendable {
    enum State: Hashable, Sendable {
        case initialized
        case uninitialized
        case conflict
    }

    let path: String
    let url: String
    let sha: String
    let state: State
}
