import SwiftUI

struct AssistantProviderEditorView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var profile: AssistantProviderProfile
    @State private var apiKey = ""
    @State private var hasSavedKey: Bool
    @State private var models: [String] = []
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var deleteConfirmation = false

    let isNew: Bool
    let onSave: (AssistantProviderProfile, String) -> Void
    let onDelete: (() -> Void)?

    private let keychain = AppServices.assistantKeychain

    init(
        profile: AssistantProviderProfile,
        isNew: Bool,
        onSave: @escaping (AssistantProviderProfile, String) -> Void,
        onDelete: (() -> Void)?
    ) {
        _profile = State(initialValue: profile)
        _hasSavedKey = State(initialValue: AppServices.assistantKeychain.apiKey(for: profile.id) != nil)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Add Provider" : "Edit Provider")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !isNew, onDelete != nil {
                    Button("Delete", role: .destructive) {
                        deleteConfirmation = true
                    }
                }
            }
            .padding(16)

            Divider()

            Form {
                Section("Connection") {
                    TextField("Name", text: $profile.name)
                    TextField("Base URL", text: $profile.baseURL)
                        .font(.system(size: 12, design: .monospaced))
                    TextField("Model ID", text: $profile.model)
                        .font(.system(size: 12, design: .monospaced))

                    if !models.isEmpty {
                        Picker("Discovered Model", selection: $profile.model) {
                            Text("Keep manual entry").tag("")
                            ForEach(models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button(isWorking ? "Checking..." : "Test Connection") {
                            refreshModels(testOnly: true)
                        }
                        .disabled(isWorking)
                        Button("Refresh Models") {
                            refreshModels(testOnly: false)
                        }
                        .disabled(isWorking)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    SecureField(
                        hasSavedKey ? "API key saved (enter to replace)" : "API key (optional)",
                        text: $apiKey
                    )
                    if hasSavedKey {
                        Button("Remove Saved API Key", role: .destructive) {
                            keychain.removeAPIKey(for: profile.id)
                            hasSavedKey = false
                            apiKey = ""
                            statusMessage = "API key removed."
                        }
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Keys are stored only in the macOS Keychain and are never written to settings.")
                }

                Section("Options") {
                    Toggle("Allow insecure HTTP", isOn: $profile.allowInsecureHTTP)
                    Toggle("Compatibility mode", isOn: $profile.compatibilityMode)
                    if profile.allowInsecureHTTP {
                        Label(
                            "Only enable insecure HTTP for a trusted local server. Remote providers should use HTTPS.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    }
                    if profile.compatibilityMode {
                        Text("Only model, messages, and stream are sent. Sampling options are omitted.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(profile, apiKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
        .alert("Delete this provider?", isPresented: $deleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text("Its API key will also be removed from the Keychain.")
        }
    }

    private func refreshModels(testOnly: Bool) {
        isWorking = true
        statusMessage = nil
        let profile = profile
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = key.isEmpty ? keychain.apiKey(for: profile.id) : key
        Task {
            do {
                let discovered = try await OpenAICompatibleClient(
                    session: AppServices.assistantURLSession
                ).fetchModels(profile: profile, apiKey: effectiveKey)
                models = discovered
                if let first = discovered.first, profile.model.isEmpty {
                    self.profile.model = first
                }
                statusMessage = testOnly
                    ? "Connected. Found \(discovered.count) model\(discovered.count == 1 ? "" : "s")."
                    : "Loaded \(discovered.count) model\(discovered.count == 1 ? "" : "s")."
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
