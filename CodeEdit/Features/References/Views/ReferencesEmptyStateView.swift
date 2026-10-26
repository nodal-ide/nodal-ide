import SwiftUI

struct ReferencesEmptyStateView: View {
    let title: String
    let description: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        CEContentUnavailableView(title, description: description, systemImage: systemImage) {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
