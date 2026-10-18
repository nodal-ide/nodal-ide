//
//  SettingsInjector.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 28/04/2023.
//

import SwiftUI

struct SettingsInjector<Content: View>: View {

    @StateObject private var settings: AnySettingsStore

    @ViewBuilder var content: Content

    init(settings: any SettingsProviding = Settings.shared, @ViewBuilder content: () -> Content) {
        self._settings = StateObject(wrappedValue: AnySettingsStore(settings))
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.settings, settings.preferences)
            .environment(\.settingsStore, settings)
    }
}
