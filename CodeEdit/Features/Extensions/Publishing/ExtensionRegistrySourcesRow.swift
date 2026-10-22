//
//  ExtensionRegistrySourcesRow.swift
//  CodeEdit
//

import SwiftUI

struct ExtensionRegistrySourcesRow: View {
    let registry: ExtensionRegistryConfiguration?
    let onCreate: () -> Void
    let onManage: () -> Void
    let onPublish: () -> Void

    var body: some View {
        if let registry {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(registry.name, systemImage: "shippingbox")
                        .font(.headline)
                    Spacer()
                    Button("Manage…", action: onManage)
                    Button("Publish…", action: onPublish)
                }
                Text(registry.workingCopyPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Branch \(registry.branch) · \(registry.catalogURL ?? "No hosted catalog URL")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        } else {
            HStack {
                Label(
                    "Create a Git-backed registry to package and publish extensions.",
                    systemImage: "shippingbox"
                )
                .foregroundStyle(.secondary)
                Spacer()
                Button("Create Registry…", action: onCreate)
            }
            .padding(.vertical, 4)
        }
    }
}
