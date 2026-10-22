import SwiftUI

/// Consistent empty/placeholder presentation for every destination in the Extensions window.
///
/// A single component keeps iconography, copy width, and action hierarchy aligned across Discover,
/// Installed, Sources, and Updates instead of each view inventing its own placeholder.
struct ExtensionEmptyState: View {
    struct Action {
        let title: String
        let systemImage: String?
        let role: ButtonRole?
        let handler: () -> Void

        init(
            _ title: String,
            systemImage: String? = nil,
            role: ButtonRole? = nil,
            handler: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.role = role
            self.handler = handler
        }
    }

    let systemImage: String
    let title: String
    let message: String
    let primaryAction: Action?
    let secondaryAction: Action?
    let minimumHeight: CGFloat

    init(
        systemImage: String,
        title: String,
        message: String,
        primaryAction: Action? = nil,
        secondaryAction: Action? = nil,
        minimumHeight: CGFloat = 260
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.minimumHeight = minimumHeight
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            actionButton(primaryAction, prominent: true)
            actionButton(secondaryAction, prominent: false)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
    }

    @ViewBuilder
    private func actionButton(_ action: Action?, prominent: Bool) -> some View {
        if let action {
            if prominent {
                Button(role: action.role, action: action.handler) {
                    actionLabel(action)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(role: action.role, action: action.handler) {
                    actionLabel(action)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: Action) -> some View {
        if let systemImage = action.systemImage {
            Label(action.title, systemImage: systemImage)
        } else {
            Text(action.title)
        }
    }
}
