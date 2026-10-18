//
//  AppSettings.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 12/04/2023.
//

import Foundation
import SwiftUI
import Combine

/// Abstraction over the app's preferences store.
///
/// ``Settings`` is the production implementation, but the store is injectable so previews and tests can
/// supply their own backing data. Views read/write through whatever store is present in the environment
/// (see `EnvironmentValues.settingsStore`), defaulting to ``Settings/shared``.
protocol SettingsProviding: AnyObject {
    var preferences: SettingsData { get set }
    var objectWillChange: ObservableObjectPublisher { get }
}

extension SettingsProviding {
    subscript<T>(_ path: WritableKeyPath<SettingsData, T>) -> T {
        get { preferences[keyPath: path] }
        set { preferences[keyPath: path] = newValue }
    }
}

/// Type-erased, observable wrapper around ``SettingsProviding`` so an injected store can be referenced
/// by a SwiftUI `@StateObject`/`@ObservedObject` (existentials don't self-conform to `ObservableObject`).
final class AnySettingsStore: ObservableObject, SettingsProviding {
    private let base: any SettingsProviding
    private var cancellable: AnyCancellable?

    init(_ base: any SettingsProviding) {
        self.base = base
        self.cancellable = base.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var preferences: SettingsData {
        get { base.preferences }
        set { base.preferences = newValue }
    }
}

/// Property wrapper that reads and writes a single ``SettingsData`` value through the injected settings
/// store, re-rendering the view when the injected preferences change.
///
/// The store is resolved from `EnvironmentValues.settingsStore` and defaults to ``Settings/shared``, so
/// injection is opt-in. `EnvironmentValues.settings` is observed (not read) so that a change to any
/// preference invalidates the view.
@propertyWrapper
struct AppSettings<T>: DynamicProperty where T: Equatable {

    @Environment(\.settingsStore)
    private var store: any SettingsProviding

    @Environment(\.settings)
    private var settings: SettingsData

    let keyPath: WritableKeyPath<SettingsData, T>

    init(_ keyPath: WritableKeyPath<SettingsData, T>) {
        self.keyPath = keyPath
        self._store = Environment(\.settingsStore)
        self._settings = Environment(\.settings)
    }

    var wrappedValue: T {
        get {
            store.preferences[keyPath: keyPath]
        }
        nonmutating set {
            store.preferences[keyPath: keyPath] = newValue
        }
    }

    var projectedValue: Binding<T> {
        Binding {
            store.preferences[keyPath: keyPath]
        } set: {
            store.preferences[keyPath: keyPath] = $0
        }
    }
}

struct SettingsStoreEnvironmentKey: EnvironmentKey {
    static var defaultValue: any SettingsProviding { Settings.shared }
}

struct SettingsDataEnvironmentKey: EnvironmentKey {
    static var defaultValue: SettingsData = .init()
}

extension EnvironmentValues {
    /// The injected settings store used by ``AppSettings``.
    var settingsStore: any SettingsProviding {
        get { self[SettingsStoreEnvironmentKey.self] }
        set { self[SettingsStoreEnvironmentKey.self] = newValue }
    }

    /// The injected preferences snapshot observed by ``AppSettings`` for view invalidation.
    var settings: SettingsDataEnvironmentKey.Value {
        get { self[SettingsDataEnvironmentKey.self] }
        set { self[SettingsDataEnvironmentKey.self] = newValue }
    }
}
