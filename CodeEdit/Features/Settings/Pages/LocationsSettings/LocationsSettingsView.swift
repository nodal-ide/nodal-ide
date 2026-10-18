//
//  LocationSettingsView.swift
//  CodeEdit
//
//  Created by Raymond Vleeshouwer on 02/04/23.
//

import SwiftUI

/// A view that implements the `Locations` settings section
struct LocationsSettingsView: View {
    var body: some View {
        SettingsForm {
            Section {
                applicationSupportLocation
                settingsLocation
                themesLocation
                extensionsLocation
            }
        }
    }
}

private extension LocationsSettingsView {
    @ViewBuilder private var applicationSupportLocation: some View {
        ExternalLink(destination: AppServices.settings.baseURL) {
            Text("Application Support")
            Text(AppServices.settings.baseURL.path)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var settingsLocation: some View {
        ExternalLink(destination: AppServices.themeModel.settingsURL) {
            Text("Settings")
            Text(AppServices.themeModel.settingsURL.path)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var themesLocation: some View {
        ExternalLink(destination: AppServices.themeModel.themesURL) {
            Text("Themes")
            Text(AppServices.themeModel.themesURL.path)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var extensionsLocation: some View {
        ExternalLink(destination: AppServices.themeModel.extensionsURL) {
            Text("Extensions")
            Text(AppServices.themeModel.extensionsURL.path())
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
