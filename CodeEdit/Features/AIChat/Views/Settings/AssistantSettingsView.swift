import SwiftUI

struct AssistantSettingsView: View {
    @AppSettings(\.assistant)
    private var assistant

    @State private var editingProfile: AssistantProviderProfile?
    @State private var newProfile: AssistantProviderProfile?

    private let keychain = AppServices.assistantKeychain

    var body: some View {
        SettingsForm {
            Section {
                if assistant.profiles.isEmpty {
                    Text("No providers configured")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(assistant.profiles) { profile in
                        Button {
                            editingProfile = profile
                        } label: {
                            providerRow(profile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                HStack {
                    Spacer()
                    Menu("Add Provider...") {
                        ForEach(AssistantProviderPreset.allCases) { preset in
                            Button(preset.title) {
                                newProfile = preset.makeProfile()
                            }
                        }
                    }
                    .fixedSize()
                }
                .padding(.top, 10)
            }

            if !assistant.profiles.isEmpty {
                Section("Default Provider") {
                    Picker("Default Provider", selection: $assistant.defaultProfileID) {
                        Text("First available").tag(nil as UUID?)
                        ForEach(assistant.profiles) { profile in
                            Text(profile.name).tag(profile.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
            }

            Section {
                Toggle("Stream responses", isOn: $assistant.streamResponses)
                SliderRow(
                    title: "Temperature",
                    value: $assistant.temperature,
                    range: 0...2,
                    step: 0.1,
                    valueText: String(format: "%.1f", assistant.temperature)
                )
                Stepper(
                    "Max output tokens: \(assistant.maxOutputTokens)",
                    value: $assistant.maxOutputTokens,
                    in: 128...32_768,
                    step: 128
                )
                Stepper(
                    "Context window: \(assistant.contextWindowTokens)",
                    value: $assistant.contextWindowTokens,
                    in: 1_024...1_000_000,
                    step: 1_024
                )
            } header: {
                Text("Generation")
            } footer: {
                Text("The context window is used for budgeting. The provider's model limit still applies.")
            }

            Section("Context") {
                Toggle("Include diagnostics by default", isOn: $assistant.includeDiagnosticsByDefault)
                Toggle("Include tasks by default", isOn: $assistant.includeTasksByDefault)
                Toggle("Prepare workspace retrieval", isOn: $assistant.retrieveWorkspaceExcerpts)
            }

            Section {
                Toggle("Save conversation history", isOn: $assistant.saveHistory)
                ForEach(assistant.profiles) { profile in
                    if isRemote(profile) {
                        Toggle(
                            "Allow remote workspace context for \(profile.name)",
                            isOn: remoteConsentBinding(for: profile)
                        )
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Provider profiles and API keys are global. API keys are stored in the macOS Keychain.")
            }
        }
        .sheet(item: $editingProfile) { profile in
            AssistantProviderEditorView(
                profile: profile,
                isNew: false,
                onSave: { updated, apiKey in
                    save(updated, apiKey: apiKey)
                    editingProfile = nil
                },
                onDelete: {
                    delete(profile)
                    editingProfile = nil
                }
            )
        }
        .sheet(item: $newProfile) { profile in
            AssistantProviderEditorView(
                profile: profile,
                isNew: true,
                onSave: { updated, apiKey in
                    save(updated, apiKey: apiKey)
                    newProfile = nil
                },
                onDelete: nil
            )
        }
    }

    private func providerRow(_ profile: AssistantProviderProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isRemote(profile) ? "cloud" : "desktopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .foregroundStyle(.primary)
                    if assistant.defaultProfileID == profile.id {
                        Text("Default")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
                Text(profile.baseURL.isEmpty ? "No endpoint" : profile.baseURL)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(profile.model.isEmpty ? "No model selected" : profile.model)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if keychain.apiKey(for: profile.id) != nil {
                Image(systemName: "key.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("API key saved in Keychain")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func isRemote(_ profile: AssistantProviderProfile) -> Bool {
        guard let endpoint = try? AssistantEndpoint(
            baseURLString: profile.baseURL,
            allowInsecureHTTP: profile.allowInsecureHTTP
        ) else {
            return !profile.isLocal
        }
        return !endpoint.isLoopback
    }

    private func remoteConsentBinding(for profile: AssistantProviderProfile) -> Binding<Bool> {
        Binding {
            assistant.remoteWorkspaceContextConsent[profile.id] == true
        } set: { value in
            assistant.remoteWorkspaceContextConsent[profile.id] = value
        }
    }

    private func save(_ profile: AssistantProviderProfile, apiKey: String) {
        if let index = assistant.profiles.firstIndex(where: { $0.id == profile.id }) {
            if assistant.profiles[index].baseURL != profile.baseURL {
                assistant.remoteWorkspaceContextConsent.removeValue(forKey: profile.id)
            }
            assistant.profiles[index] = profile
        } else {
            assistant.profiles.append(profile)
        }
        if assistant.defaultProfileID == nil {
            assistant.defaultProfileID = profile.id
        }
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keychain.setAPIKey(apiKey, for: profile.id)
        }
    }

    private func delete(_ profile: AssistantProviderProfile) {
        assistant.profiles.removeAll { $0.id == profile.id }
        assistant.remoteWorkspaceContextConsent.removeValue(forKey: profile.id)
        if assistant.defaultProfileID == profile.id {
            assistant.defaultProfileID = assistant.profiles.first?.id
        }
        keychain.removeAPIKey(for: profile.id)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: $value, in: range, step: step)
                .frame(width: 160)
            Text(valueText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
