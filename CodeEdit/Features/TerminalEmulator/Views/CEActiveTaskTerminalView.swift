//
//  CEActiveTaskTerminalView.swift
//  CodeEdit
//
//  Created by Khan Winter on 7/14/25.
//

import AppKit
import SwiftTerm

class CEActiveTaskTerminalView: CELocalShellTerminalView {
    var activeTask: CEActiveTask

    /// Optional tap that receives raw output chunks (used by problem matchers).
    var outputTap: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        outputTap?(slice)
        super.dataReceived(slice: slice)
    }

    var isUserCommandRunning: Bool {
        activeTask.status == .running || activeTask.status == .stopped
    }

    init(activeTask: CEActiveTask) {
        self.activeTask = activeTask
        super.init(frame: .zero)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startProcess(
        workspaceURL url: URL?,
        shell: Shell? = nil,
        environment: [String] = [],
        interactive: Bool = true
    ) {
        let terminalSettings = Settings.shared.preferences.terminal

        var terminalEnvironment: [String] = Terminal.getEnvironmentVariables()
        terminalEnvironment.append("TERM_PROGRAM=CodeEditApp_Terminal")

        guard let (shell, shellPath) = getShell(shell, userSetting: terminalSettings.shell) else {
            return
        }
        let shellArgs = ["-lic", activeTask.task.command]

        terminalEnvironment.append(contentsOf: environment)
        // Activate the project's runtimes (PATH) before the task's own env so the task can override it.
        let runtimeEnvironment = RuntimeEnvironment.shared.cachedEnvironment(for: url)
        terminalEnvironment.append(contentsOf: runtimeEnvironment.map { "\($0.key)=\($0.value)" })
        terminalEnvironment.append("\(ShellIntegration.Variables.disableHistory)=1")
        terminalEnvironment.append(
            contentsOf: activeTask.task.environmentVariables.map({ $0.key + "=" + $0.value })
        )

        sendOutputMessage("Starting task: " + self.activeTask.task.name)
        sendOutputMessage(self.activeTask.task.command)
        newline()

        process.startProcess(
            executable: shellPath,
            args: shellArgs,
            environment: terminalEnvironment,
            execName: shell.rawValue,
            currentDirectory: URL(filePath: activeTask.task.workingDirectory, relativeTo: url).absolutePath
        )
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        activeTask.handleProcessFinished(terminationStatus: exitCode ?? 1)
    }

    func sendOutputMessage(_ message: String) {
        sendSpecialSequence()
        feed(text: message)
        newline()
    }

    func sendSpecialSequence() {
        let start: [UInt8] = [0x1B, 0x5B, 0x37, 0x6D]
        let end: [UInt8] = [0x1B, 0x5B, 0x30, 0x6D]
        feed(byteArray: start[0..<start.count])
        feed(text: " * ")
        feed(byteArray: end[0..<end.count])
        feed(text: " ")
    }

    func newline() {
        // cr cr lf
        feed(byteArray: [13, 13, 10])
    }

    func runningPID() -> pid_t? {
        if process.shellPid != 0 {
            return process.shellPid
        }
        return nil
    }

    func getBufferAsString() -> String {
        terminal.getText(
            start: .init(col: 0, row: 0),
            end: .init(col: terminal.cols, row: terminal.rows + terminal.buffer.yDisp)
        )
    }
}
