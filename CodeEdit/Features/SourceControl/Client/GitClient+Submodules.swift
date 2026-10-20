import Foundation

extension GitClient {
    /// Lists all submodules registered for this repository, including nested submodules.
    ///
    /// This uses a single `git submodule status --recursive` call for paths, SHAs, and
    /// states, plus one `git config` read of `.gitmodules` for display URLs.
    func listSubmodules() async throws -> [GitSubmodule] {
        let output: String
        do {
            output = try await run("submodule status --recursive")
        } catch GitClientError.notGitRepository {
            return []
        }

        let statusLines = output
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !statusLines.isEmpty else { return [] }

        let urlsByPath = await submoduleURLsByPath()
        return statusLines.compactMap { line in
            guard var submodule = Self.parseSubmoduleStatusLine(line) else { return nil }
            if let url = urlsByPath[submodule.path] {
                submodule = GitSubmodule(
                    path: submodule.path,
                    url: url,
                    sha: submodule.sha,
                    state: submodule.state
                )
            }
            return submodule
        }
    }

    func submoduleUpdate(path: String, initialize: Bool, recursive: Bool) async throws {
        var args = "submodule update"
        if initialize { args += " --init" }
        if recursive { args += " --recursive" }
        args += " -- \(path.shellSingleQuoted)"
        _ = try await run(args)
    }

    func submoduleDeinit(path: String) async throws {
        _ = try await run("submodule deinit -- \(path.shellSingleQuoted)")
    }

    /// Parses one line of `git submodule status --recursive` output.
    ///
    /// The format is `<state><sha> <path>[ (<describe>)]`, where the state prefix is one
    /// of ` `, `-`, `+`, or `U`. Paths may contain spaces, which is why the path is not
    /// split into components.
    static func parseSubmoduleStatusLine(_ line: String) -> GitSubmodule? {
        let line = line.trimmingCharacters(in: .newlines)
        guard !line.isEmpty else { return nil }

        var state: GitSubmodule.State = .initialized
        var remainder = line[...]
        switch remainder.first {
        case "-":
            state = .uninitialized
            remainder = remainder.dropFirst()
        case "U":
            state = .conflict
            remainder = remainder.dropFirst()
        case "+", " ":
            remainder = remainder.dropFirst()
        default:
            break
        }

        remainder = remainder.drop(while: { $0 == " " || $0 == "\t" })
        guard let shaEnd = remainder.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }
        let sha = String(remainder[..<shaEnd])
        guard sha.count >= 7, sha.allSatisfy(\.isHexDigit) else { return nil }

        var path = String(remainder[remainder.index(after: shaEnd)...])
            .trimmingCharacters(in: .whitespaces)
        if path.hasSuffix(")"),
           let describeStart = path.range(of: " (", options: .backwards) {
            path = String(path[..<describeStart.lowerBound])
        }
        guard !path.isEmpty else { return nil }

        return GitSubmodule(path: path, url: "", sha: sha, state: state)
    }

    /// Reads submodule paths and URLs from `.gitmodules` in one call.
    private func submoduleURLsByPath() async -> [String: String] {
        let output: String
        do {
            output = try await run(
                "config --file .gitmodules --null --get-regexp '^submodule\\..*\\.(path|url)$'"
            )
        } catch {
            return [:]
        }

        var pathsByName: [String: String] = [:]
        var urlsByName: [String: String] = [:]
        for record in output.components(separatedBy: "\0") where !record.isEmpty {
            guard let separator = record.firstIndex(of: "\n") else { continue }
            let key = String(record[..<separator])
            let value = String(record[record.index(after: separator)...])
            if key.hasSuffix(".path") {
                pathsByName[String(key.dropLast(".path".count))] = value
            } else if key.hasSuffix(".url") {
                urlsByName[String(key.dropLast(".url".count))] = value
            }
        }

        var result: [String: String] = [:]
        for (name, path) in pathsByName {
            result[path] = urlsByName[name]
        }
        return result
    }
}

private extension String {
    /// Wraps the string in single quotes for safe interpolation into a shell command.
    var shellSingleQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
