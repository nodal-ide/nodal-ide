//
//  RuntimePackageManagersView.swift
//  CodeEdit
//
//  Node package manager section for the Runtime Manager window.
//

import SwiftUI

struct RuntimePackageManagersView: View {
    @ObservedObject var model: RuntimeManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Package Managers").font(.headline)
                if model.isLoadingPackages {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            if let runtime = model.nodeRuntime {
                Text("Activated for Node v\(runtime.version) via corepack.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                managerList

                HStack(spacing: 8) {
                    TextField("e.g. pnpm@9", text: $model.packageManagerInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onSubmit { Task { await model.activatePackageManager() } }
                    Button("Activate") {
                        Task { await model.activatePackageManager() }
                    }
                    .disabled(!model.packageManagerInput.contains("@"))
                    Spacer()
                }
            } else {
                Text("Install a Node.js version to manage package managers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var managerList: some View {
        VStack(spacing: 0) {
            ForEach(NodePackageManagerService.known, id: \.self) { name in
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox").foregroundStyle(.secondary)
                    Text(name).font(.system(.body, design: .monospaced))
                    Spacer()
                    if let version = model.packageManagers[name] {
                        RuntimeBadge(text: version, color: .green)
                    } else {
                        Text("not activated").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                if name != NodePackageManagerService.known.last {
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}
