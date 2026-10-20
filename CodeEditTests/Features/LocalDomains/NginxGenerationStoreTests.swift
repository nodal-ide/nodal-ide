import Foundation
import Testing
@testable import CodeEdit

struct NginxGenerationStoreTests {
    private func prefix(in directory: URL) throws -> NginxPrefix {
        let prefix = NginxPrefix(root: directory.appending(path: "nginx", directoryHint: .isDirectory))
        try prefix.createDirectories()
        return prefix
    }

    @Test
    func nextNameStartsAtOneAndIncrements() throws {
        try withTempDir { directory in
            let prefix = try prefix(in: directory)
            let store = NginxGenerationStore(prefix: prefix)

            #expect(try store.nextName() == "1")
            _ = try store.write(sites: [], listenPorts: [18080], name: "1")
            #expect(try store.nextName() == "2")
        }
    }

    @Test
    func swappingCurrentPublishesTheNewGenerationAtomically() throws {
        try withTempDir { directory in
            let prefix = try prefix(in: directory)
            let store = NginxGenerationStore(prefix: prefix)

            _ = try store.write(sites: [], listenPorts: [18080], name: "1")
            _ = try store.write(sites: [], listenPorts: [18080], name: "2")

            try store.swapCurrent(to: "1")
            #expect(store.currentName() == "1")

            try store.swapCurrent(to: "2")
            #expect(store.currentName() == "2")

            let leftovers = try FileManager.default.contentsOfDirectory(
                atPath: prefix.root.path(percentEncoded: false)
            ).filter { $0.hasPrefix("current.") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test
    func pruningKeepsOnlyTheRequestedGenerations() throws {
        try withTempDir { directory in
            let prefix = try prefix(in: directory)
            let store = NginxGenerationStore(prefix: prefix)

            for name in ["1", "2", "3"] {
                _ = try store.write(sites: [], listenPorts: [18080], name: name)
            }

            try store.prune(keeping: ["2", "3"])

            #expect(try store.generationNames().sorted() == ["2", "3"])
        }
    }

    @Test
    func removingAGenerationDeletesItsDirectory() throws {
        try withTempDir { directory in
            let prefix = try prefix(in: directory)
            let store = NginxGenerationStore(prefix: prefix)

            _ = try store.write(sites: [], listenPorts: [18080], name: "1")
            try store.remove(name: "1")

            #expect(try store.generationNames().isEmpty)
        }
    }
}
