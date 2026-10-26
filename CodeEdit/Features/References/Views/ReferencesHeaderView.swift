import SwiftUI
import CodeEditLang

@MainActor
struct ReferencesHeaderView: View {
    @ObservedObject var session: ReferencesSession
    @Binding var filter: ReferencesFilter
    let hasCurrentFile: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: (session.target?.kind ?? .unknown).systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.target?.identifier ?? "References")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let container = session.target?.container, !container.isEmpty {
                        Text(container)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(container)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    session.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear references")
                .disabled(session.phase == .idle)
                .accessibilityLabel("Clear references")
            }

            filterField

            Picker("Scope", selection: $filter.scope) {
                ForEach(ReferencesFilter.Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("Reference scope")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .onChange(of: hasCurrentFile) { _, hasFile in
            if !hasFile, filter.scope == .currentFile {
                filter.scope = .project
            }
        }
    }

    private var filterField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("Filter references", text: $filter.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .accessibilityLabel("Filter references")
            if !filter.query.isEmpty {
                Button {
                    filter.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
