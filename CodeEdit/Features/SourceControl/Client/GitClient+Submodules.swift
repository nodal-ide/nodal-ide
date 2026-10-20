import Foundation

extension GitClient {
    func listSubmodules() async throws -> [GitSubmodule] {
        let output: String
        do {
            output = try await run("submodule status --recursive")
        } catch GitClientError.notGitRepository {
            return []
        }

        return output
            .components(separatedBy: "\n")
            .compactMap(parseSubmoduleLine)
    }

    func submoduleUpdate(path: String, initialize: Bool, recursive: Bool) async throws {
        var args = "submodule update"
        if initialize { args += " --init" }
        if recursive { args += " --recursive" }
        args += " -- '\(path)'"
        _ = try await run(args)
    }

    func submoduleDeinit(path: String) async throws {
        _ = try await run("submodule deinit -- '\(path)'")
    }

    private func parseSubmoduleLine(_ line: String) -> GitSubmodule? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 41 else { return nil }

        let stateChar = trimmed.first
        let state: GitSubmodule.State
        switch stateChar {
        case "-": state = .uninitialized
        case "U": state = .conflict
        default: state = .initialized
        }

        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let parts = rest.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let sha = parts[0]
        let path = parts[1]

        return GitSubmodule(path: path, url: "", sha: sha, state: state)
    }
}
