//
//  ExtensionPublishReviewView.swift
//  CodeEdit
//

import SwiftUI

struct ExtensionPublishReviewView: View {
    let preparation: ExtensionPublishPreparation
    @Binding var pushAfterCommit: Bool
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let onBack: () -> Void
    let onPublish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    releaseSection
                    destinationSection
                    if !preparation.unrelatedChanges.isEmpty {
                        unrelatedSection
                    }
                    diffSection
                    Toggle("Push after committing", isOn: $pushAfterCommit)
                        .disabled(preparation.remote == nil)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Button("Back", action: onBack)
                    .disabled(isWorking)
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Publish", action: onPublish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
            .padding(20)
        }
    }

    private var releaseSection: some View {
        GroupBox("Release") {
            VStack(alignment: .leading, spacing: 6) {
                labeled("Extension", preparation.extensionID)
                labeled("Version", preparation.version)
                labeled("Name", preparation.release.catalogName)
                labeled("Publisher", preparation.release.catalogPublisher)
                labeled("ZIP size", preparation.artifact.byteCount.formatted(.byteCount(style: .file)))
                labeled("SHA-256", preparation.artifact.integrity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var destinationSection: some View {
        GroupBox("Destination") {
            VStack(alignment: .leading, spacing: 6) {
                labeled("Registry", preparation.configuration.name)
                labeled("Branch", preparation.branch)
                labeled("Remote", preparation.remote ?? "Local only")
                labeled("Commit as", preparation.commitIdentity)
                labeled("Package", preparation.packageRelativePath)
                labeled("Catalog", preparation.catalogRelativePath)
                if !preparation.latestAdvanced {
                    Text("This release will not replace the catalog’s latest version.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var unrelatedSection: some View {
        GroupBox("Unrelated Changes") {
            VStack(alignment: .leading, spacing: 4) {
                Text("These changes will remain uncommitted:")
                    .foregroundStyle(.secondary)
                ForEach(preparation.unrelatedChanges.prefix(8)) { change in
                    Text("\(change.code)  \(change.path)")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
                if preparation.unrelatedChanges.count > 8 {
                    Text("…and \(preparation.unrelatedChanges.count - 8) more")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var diffSection: some View {
        GroupBox("Catalog Diff") {
            Text(preparation.catalogDiff.isEmpty ? "No catalog changes." : preparation.catalogDiff)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}
