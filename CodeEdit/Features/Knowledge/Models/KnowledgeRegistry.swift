//
//  KnowledgeRegistry.swift
//  CodeEdit
//
//  Aggregates knowledge sources: built-in, extension-contributed and user-installed.
//

import Foundation
import CodeEditLang

/// Discovers the knowledge bases available to the app.
final class KnowledgeRegistry {
    static let shared = KnowledgeRegistry()

    private(set) var sources: [KnowledgeSource] = []

    private init() {
        reload()
    }

    /// Re-discovers all sources.
    func reload() {
        var result: [KnowledgeSource] = [BuiltinKnowledge.source]
        result.append(contentsOf: extensionSources())
        result.append(contentsOf: userSources())
        result.append(contentsOf: docsetSources())
        sources = result
    }

    /// Imports a Dash/Zeal `.docset` bundle into the user knowledge folder.
    func importDocset(from source: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.docsetDirectory, withIntermediateDirectories: true)
        let destination = Self.docsetDirectory.appending(path: source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        KnowledgeSearchIndex.shared.invalidate()
        reload()
    }

    // MARK: - Private

    private func docsetSources() -> [KnowledgeSource] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: Self.docsetDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.filter { $0.pathExtension == "docset" }.compactMap { url in
            guard let result = DocsetBuilder.load(url) else { return nil }
            return KnowledgeSource(
                id: "docset/\(url.deletingPathExtension().lastPathComponent)",
                title: result.title,
                subtitle: "Docset",
                storage: .disk(root: result.documents),
                index: result.index
            )
        }
    }

    private func extensionSources() -> [KnowledgeSource] {
        var result: [KnowledgeSource] = []

        for ext in LanguageExtensionStore.shared.globalExtensions() {
            guard let contributions = ext.manifest.contributes?.knowledge else { continue }
            for contribution in contributions {
                let root = ext.root.appending(path: contribution.root ?? ".")
                let indexURL = root.appending(path: contribution.index ?? "index.json")
                guard let data = try? Data(contentsOf: indexURL),
                      let index = try? JSONDecoder().decode(KnowledgeIndex.self, from: data) else {
                    continue
                }
                result.append(
                    KnowledgeSource(
                        id: "\(ext.id)/\(contribution.id)",
                        title: contribution.title,
                        subtitle: ext.name,
                        storage: .disk(root: root),
                        index: index
                    )
                )
            }
        }
        return result
    }

    private func userSources() -> [KnowledgeSource] {
        let directory = Self.userKnowledgeDirectory
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.compactMap { entry in
            let indexURL = entry.appending(path: "index.json")
            guard let data = try? Data(contentsOf: indexURL),
                  let index = try? JSONDecoder().decode(KnowledgeIndex.self, from: data) else {
                return nil
            }
            return KnowledgeSource(
                id: "user/\(entry.lastPathComponent)",
                title: index.title,
                subtitle: index.subtitle,
                storage: .disk(root: entry),
                index: index
            )
        }
    }

    static var userKnowledgeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "CodeEdit/Knowledge", directoryHint: .isDirectory)
    }

    static var docsetDirectory: URL {
        userKnowledgeDirectory.appending(path: "Docsets", directoryHint: .isDirectory)
    }
}
