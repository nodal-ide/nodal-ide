//
//  ExtensionPublishResultView.swift
//  CodeEdit
//

import SwiftUI

struct ExtensionPublishResultView: View {
    let result: ExtensionPublishResult
    @Binding var retrySucceeded: Bool
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let onRetry: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(color)
            Text(title)
                .font(.title2.weight(.semibold))
            Text("\(result.preparation.extensionID) \(result.preparation.version)")
                .foregroundStyle(.secondary)
            if case let .pushFailed(commitSHA, message) = result.outcome, !retrySucceeded {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                labeled("Local commit", commitSHA)
                Button("Retry Push", action: onRetry)
                    .disabled(isWorking)
            } else {
                Text("Commit \(commitSHA)")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                if retrySucceeded {
                    Label(
                        "The commit is now on \(result.preparation.remote ?? "the remote").",
                        systemImage: "checkmark"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            if isWorking {
                ProgressView().controlSize(.small)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    private var title: String {
        switch result.outcome {
        case .committedLocally:
            return "Committed Locally"
        case .pushed:
            return "Published"
        case .pushFailed:
            return retrySucceeded ? "Published" : "Committed Locally; Push Failed"
        }
    }

    private var symbol: String {
        switch result.outcome {
        case .committedLocally:
            return "checkmark.circle"
        case .pushed:
            return "checkmark.circle.fill"
        case .pushFailed:
            return retrySucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch result.outcome {
        case .committedLocally:
            return .secondary
        case .pushed:
            return .green
        case .pushFailed:
            return retrySucceeded ? .green : .orange
        }
    }

    private var commitSHA: String {
        switch result.outcome {
        case .committedLocally(let sha), .pushed(let sha), .pushFailed(let sha, _):
            return sha
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
