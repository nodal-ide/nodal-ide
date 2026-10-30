//
//  ThemeSettingThemeRow.swift
//  CodeEdit
//
//  Created by Austin Condiff on 4/3/23.
//

import SwiftUI

struct ThemeSettingsThemeRow: View {
    @Binding var theme: Theme
    var active: Bool

    @ObservedObject private var themeModel: ThemeModel = AppServices.themeModel

    @State private var isHovering = false

    @State private var deleteConfirmationIsPresented = false

    private var themeSubtitle: String {
        guard let packID = theme.source.packID, !packID.isEmpty else {
            return theme.author
        }
        return "\(theme.author) · \(theme.source.displayName)"
    }

    var body: some View {
        HStack {
            Image(systemName: "checkmark")
                .opacity(active ? 1 : 0)
                .font(.system(size: 10.5, weight: .bold))
            VStack(alignment: .leading) {
                Text(theme.displayName)
                Text(themeSubtitle)
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !active {
                Button {
                    themeModel.activateTheme(theme)
                } label: {
                    Text("Choose")
                }
                .buttonStyle(.bordered)
                .opacity(isHovering ? 1 : 0)
            }
            ThemeSettingsColorPreview(theme)
            Menu {
                Button("Details...") {
                    themeModel.detailsTheme = theme
                    themeModel.detailsIsPresented = true
                }
                Button("Duplicate...") {
                    if let fileURL = theme.fileURL {
                        themeModel.duplicate(fileURL)
                    }
                }
                Button("Export...") {
                    ThemeFilePanels.export(theme, from: themeModel)
                }
                .disabled(!theme.isEditable)
                Divider()
                Button("Delete...") {
                    deleteConfirmationIsPresented = true
                }
                .disabled(!theme.isEditable)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
            }
            .buttonStyle(.icon)
        }
        .padding(10)
        .onHover { hovering in
            isHovering = hovering
        }
        .alert(
            Text("Are you sure you want to delete the theme “\(theme.displayName)”?"),
            isPresented: $deleteConfirmationIsPresented
        ) {
            Button("Delete Theme") {
                themeModel.delete(theme)
            }
            Button("Cancel") {
                deleteConfirmationIsPresented = false
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
