//
//  UtilityAreaTerminalTab.swift
//  CodeEdit
//
//  Created by Austin Condiff on 5/26/23.
//

import SwiftUI

struct UtilityAreaTerminalTab: View {
    @ObservedObject var terminal: UtilityAreaTerminal

    var removeTerminals: (_ ids: Set<UUID>) -> Void

    var isSelected: Bool

    var selectedIDs: Set<UUID>

    @FocusState private var isFocused: Bool

    /// A small indicator for the terminal's running state / last command result.
    @ViewBuilder private var activityIndicator: some View {
        if terminal.isRunning {
            ProgressView()
                .controlSize(.mini)
                .help("A command is running")
        } else if let code = terminal.lastExitCode {
            Circle()
                .fill(code == 0 ? Color.green : Color.red)
                .frame(width: 6, height: 6)
                .help(code == 0 ? "Last command succeeded" : "Last command exited with code \(code)")
        }
    }

    var body: some View {
        let terminalTitle = Binding<String>(
            get: {
                self.terminal.title
            }, set: {
                if $0.trimmingCharacters(in: .whitespaces) == "" && !isFocused {
                    self.terminal.title = self.terminal.terminalTitle
                    self.terminal.customTitle = false
                } else {
                    self.terminal.title = $0
                    self.terminal.customTitle = true
                }
            }
        )

        HStack(spacing: 6) {
            Label {
                if #available(macOS 14, *) {
                    // Fix the icon misplacement issue introduced since macOS 14
                    TextField("Name", text: terminalTitle)
                        .focused($isFocused)
                } else {
                    // A padding is needed for macOS 13
                    TextField("Name", text: terminalTitle)
                        .focused($isFocused)
                        .padding(.leading, -8)
                }
            } icon: {
                Image(systemName: "terminal")
            }
            Spacer(minLength: 4)
            activityIndicator
        }
        .contextMenu {
            Button("Rename...") {
                isFocused = true
            }

            if selectedIDs.contains(terminal.id) && selectedIDs.count > 1 {
                Button("Kill Terminals") {
                    removeTerminals(selectedIDs)
                }
            } else {
                Button("Kill Terminal") {
                    removeTerminals([terminal.id])
                }
            }
        }
        .help(terminal.cwd?.path(percentEncoded: false) ?? terminal.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(terminalTitle.wrappedValue)
        .accessibilityIdentifier("terminalTab")
    }
}
