//
//  ExtensionRegistryGit.swift
//  CodeEdit
//
//  A small, non-interactive Git surface used by registry publishing.
//

import Foundation

struct RegistryGitClient: Sendable {
    private static let environment = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=20",
        "GIT_MERGE_AUTOEDIT": "no",
        "LC_ALL": "C"
    ]

    private let runner = CommandRunner()
    private let executable = URL(fileURLWithPath: "/usr/bin/git")

    func repositoryRoot(at url: URL) async throws -> URL {
        let output = try await run(["rev-parse", "--show-toplevel"], in: url)
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw ExtensionRegistryError.notARepository(url)
        }
        return URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
    }

    func branch(in root: URL) async throws -> String? {
        let output = try await run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: root, accepted: [0, 1])
        let value = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func headSHA(in root: URL) async throws -> String? {
        let output = try await run(["rev-parse", "--verify", "HEAD"], in: root, accepted: [0, 128])
        guard output.status == 0 else { return nil }
        let value = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func remoteURL(in root: URL, remote: String = "origin") async throws -> String? {
        let output = try await run(["remote", "get-url", remote], in: root, accepted: [0, 2, 128])
        guard output.status == 0 else { return nil }
        let value = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func commitIdentity(in root: URL) async throws -> String? {
        let output = try await run(["var", "GIT_AUTHOR_IDENT"], in: root, accepted: [0, 128])
        guard output.status == 0 else { return nil }
        let value = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: " ")
        guard parts.count >= 2 else { return value }
        return parts.dropLast(2).joined(separator: " ")
    }

    func status(in root: URL) async throws -> [ExtensionRegistryGitChange] {
        let output = try await run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: root)
        return Self.parseStatus(output.stdout)
    }

    func add(paths: [String], in root: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(["add", "--"] + paths, in: root)
    }

    func reset(paths: [String], in root: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(["reset", "--quiet", "--"] + paths, in: root)
    }

    func commit(paths: [String], message: String, in root: URL) async throws -> String {
        guard !paths.isEmpty else {
            throw ExtensionRegistryError.invalidConfiguration("No registry files were selected to commit.")
        }
        _ = try await run(["commit", "--quiet", "-m", message, "--"] + paths, in: root)
        guard let sha = try await headSHA(in: root) else {
            throw ExtensionRegistryError.ioFailure("Git did not create a commit.")
        }
        return sha
    }

    func commitFiles(_ sha: String, in root: URL) async throws -> [String] {
        let output = try await run(
            ["show", "--pretty=format:", "--name-only", "-z", sha],
            in: root
        )
        return output.stdout
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func push(branch: String, remote: String, in root: URL) async throws -> CommandOutput {
        try await run(["push", remote, "HEAD:refs/heads/\(branch)"], in: root)
    }

    func run(
        _ arguments: [String],
        in directory: URL,
        accepted: Set<Int32> = [0]
    ) async throws -> CommandOutput {
        do {
            return try await runner.run(
                executable: executable,
                arguments: arguments,
                currentDirectory: directory,
                environment: Self.environment,
                acceptedStatuses: accepted
            )
        } catch let error as CommandRunnerError {
            throw ExtensionRegistryError.command(error.localizedDescription)
        }
    }

    static func parseStatus(_ output: String) -> [ExtensionRegistryGitChange] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)
        var changes: [ExtensionRegistryGitChange] = []
        var index = 0
        while index < fields.count {
            let record = String(fields[index])
            index += 1
            guard record.utf8.count >= 4 else { continue }
            let code = String(record.prefix(2))
            let path = String(record.dropFirst(3))
            if code.contains("R") || code.contains("C"), index < fields.count {
                index += 1
            }
            changes.append(ExtensionRegistryGitChange(code: code, path: path))
        }
        return changes
    }
}
