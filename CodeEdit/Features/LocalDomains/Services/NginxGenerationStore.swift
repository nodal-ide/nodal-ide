import Darwin
import Foundation

enum NginxGenerationStoreError: Error, Equatable, LocalizedError {
    case symlinkSwapFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .symlinkSwapFailed(let code):
            return "Could not atomically switch the nginx config generation (errno \(code))."
        }
    }
}

/// Owns generation directories and the `current` symlink. Writes are staged in a new generation and
/// published with a single atomic `rename(2)`, so the running master never observes a partial config.
struct NginxGenerationStore {
    let prefix: NginxPrefix

    func nextName() throws -> String {
        let highest = try generationNames()
            .compactMap { Int($0) }
            .max() ?? 0
        return String(highest + 1)
    }

    func generationNames() throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: prefix.generationsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }

    func write(
        sites: [NginxSiteConfiguration],
        listenPorts: Set<Int>,
        name: String
    ) throws -> URL {
        try NginxGenerationWriter.write(
            sites: sites,
            listenPorts: listenPorts,
            prefix: prefix,
            generationName: name
        )
    }

    func swapCurrent(to name: String) throws {
        let target = "generations/\(name)"
        let temporary = prefix.root.appending(path: "current.\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(
            atPath: temporary.path(percentEncoded: false),
            withDestinationPath: target
        )

        let temporaryPath = temporary.path(percentEncoded: false)
        let currentPath = prefix.currentSymlink.path(percentEncoded: false)
        guard rename(temporaryPath, currentPath) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw NginxGenerationStoreError.symlinkSwapFailed(errno: code)
        }
    }

    func currentName() -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(
            atPath: prefix.currentSymlink.path(percentEncoded: false)
        ) else {
            return nil
        }
        let name = URL(filePath: target).lastPathComponent
        return name.isEmpty ? nil : name
    }

    func remove(name: String) throws {
        try FileManager.default.removeItem(at: prefix.generationDirectory(named: name))
    }

    /// Deletes every generation directory that is not in `names`, keeping disk usage bounded.
    func prune(keeping names: Set<String>) throws {
        for name in try generationNames() where !names.contains(name) {
            try remove(name: name)
        }
    }
}
