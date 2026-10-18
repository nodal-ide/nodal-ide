//
//  WorkspaceStateStore.swift
//  CodeEdit
//
//  Persists per-workspace UI state (window size, open tabs, panel sizes, collapsed flags) in
//  `UserDefaults`, keyed by the workspace URL. Extracted from `WorkspaceDocument` so the document
//  no longer owns persistence details.
//

import Foundation

/// Stores small pieces of workspace-scoped UI state as a single `UserDefaults` dictionary entry,
/// keyed by the workspace URL. Callers read/write typed values through ``WorkspaceStateKey``.
struct WorkspaceStateStore {
    private let defaults: UserDefaults
    private let key: String

    init(fileURL: URL?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "workspaceState-\(fileURL?.absoluteString ?? "")"
    }

    private var state: [String: Any] {
        get { defaults.object(forKey: key) as? [String: Any] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }

    /// Returns the stored value for `key`, if any.
    func value(for key: WorkspaceStateKey) -> Any? {
        state[key.rawValue]
    }

    /// Stores `value` for `key`; a `nil` value removes the entry.
    func set(_ value: Any?, for key: WorkspaceStateKey) {
        var state = self.state
        if let value {
            state.updateValue(value, forKey: key.rawValue)
        } else {
            state.removeValue(forKey: key.rawValue)
        }
        self.state = state
    }
}
