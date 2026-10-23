//
//  AddExtensionSourceSheet.swift
//  CodeEdit
//

import SwiftUI

struct AddExtensionSourceSheet: View {
    @EnvironmentObject private var marketplace: ExtensionMarketplaceViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var providerID: ExtensionSourceProviderID
    @State private var revision = ""
    @State private var trustImmediately = false
    @State private var errorMessage: String?
    private let source: ExtensionSource?

    init(source: ExtensionSource? = nil) {
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _location = State(initialValue: source?.location.absoluteString ?? "")
        _providerID = State(initialValue: source?.providerID ?? .gitRepository)
        _revision = State(initialValue: source?.revision ?? "")
        _trustImmediately = State(initialValue: source?.isTrusted ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(source == nil ? "Add Extension Source" : "Edit Extension Source")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name, prompt: Text("Team Registry"))
                Picker("Type", selection: $providerID) {
                    Text("Git Repository").tag(ExtensionSourceProviderID.gitRepository)
                    Text("HTTPS Static Index").tag(ExtensionSourceProviderID.httpsStaticIndex)
                }
                .pickerStyle(.segmented)
                TextField(
                    providerID == .gitRepository ? "Repository URL" : "Catalog URL",
                    text: $location,
                    prompt: Text(
                        providerID == .gitRepository
                            ? "https://github.com/team/registry.git"
                            : "https://example.com/extensions.json"
                    )
                )
                .textFieldStyle(.roundedBorder)
                if providerID == .gitRepository {
                    TextField(
                        "Revision",
                        text: $revision,
                        prompt: Text("Branch, tag, or commit (optional)")
                    )
                }
                if source == nil {
                    Toggle("Trust this source", isOn: $trustImmediately)
                }
            }
            .onChange(of: providerID) {
                errorMessage = nil
                if providerID != .gitRepository { revision = "" }
            }
            Text(
                "A trusted source can provide catalog metadata and package downloads. " +
                    "Git sources use your configured SSH agent or Git credentials. Trust does not " +
                    "authenticate publishers or grant consent to native code. You can add the source " +
                    "without trusting it and review it first."
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(source == nil ? "Add Source" : "Save Changes") { saveSource() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || location.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func saveSource() {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = providerID == .gitRepository
                ? GitRepositoryLocation.normalizedURL(from: trimmedLocation)
                : URL(string: trimmedLocation) else {
            errorMessage = providerID == .gitRepository
                ? "Enter an HTTPS, SSH, or local Git repository URL."
                : "Enter a valid HTTPS catalog URL."
            return
        }
        let normalizedRevision = providerID == .gitRepository
            ? GitRepositoryLocation.normalizedRevision(revision)
            : nil
        guard GitRepositoryLocation.isValidRevision(normalizedRevision) else {
            errorMessage = "Use a branch, tag, or commit name without spaces or revision operators."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let source {
            Task {
                do {
                    try await marketplace.updateSource(
                        source,
                        name: trimmedName,
                        location: url,
                        providerID: providerID,
                        revision: normalizedRevision
                    )
                    dismiss()
                } catch {
                    errorMessage = sourceErrorDescription(error)
                }
            }
            return
        }
        do {
            try marketplace.addSource(
                name: trimmedName,
                location: url,
                providerID: providerID,
                revision: normalizedRevision,
                trustImmediately: trustImmediately
            )
            dismiss()
        } catch {
            errorMessage = sourceErrorDescription(error)
        }
    }

    private func sourceErrorDescription(_ error: Error) -> String {
        switch error {
        case ExtensionSourceCollectionError.invalidSourceLocation:
            return providerID == .gitRepository
                ? "The Git repository URL is invalid or contains unsupported credentials."
                : "The catalog URL must use HTTPS and cannot contain credentials, a query, or a fragment."
        case ExtensionSourceCollectionError.invalidSourceConfiguration:
            return "Choose a source name with 1–128 characters and a valid revision."
        case ExtensionSourceCollectionError.duplicateSourceLocation:
            return "A source with this provider, location, and revision already exists."
        default:
            return error.localizedDescription
        }
    }
}
