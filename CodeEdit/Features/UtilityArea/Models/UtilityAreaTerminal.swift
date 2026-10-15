//
//  UtilityAreaTerminal.swift
//  CodeEdit
//
//  Created by Khan Winter on 7/27/24.
//

import Foundation

/// The orientation of a terminal split.
enum TerminalSplitAxis: String {
    case horizontal
    case vertical
}

final class UtilityAreaTerminal: ObservableObject, Identifiable, Equatable {
    let id: UUID
    @Published var url: URL
    @Published var title: String
    @Published var terminalTitle: String
    @Published var shell: Shell?
    @Published var customTitle: Bool
    /// The shell's current working directory, tracked via shell integration (OSC 7).
    @Published var cwd: URL?
    /// Whether a command is currently running (tracked via shell integration).
    @Published var isRunning: Bool = false
    /// The exit code of the last finished command, if known.
    @Published var lastExitCode: Int?

    init(id: UUID, url: URL, title: String, shell: Shell?) {
        self.id = id
        self.title = title
        self.terminalTitle = title
        self.url = url
        self.shell = shell
        self.customTitle = false
    }

    static func == (lhs: UtilityAreaTerminal, rhs: UtilityAreaTerminal) -> Bool {
        lhs.id == rhs.id
    }
}
