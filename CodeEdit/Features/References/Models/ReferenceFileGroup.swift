import Foundation
import CodeEditLang

struct ReferenceFileGroup: Identifiable, Equatable {
    let fileURL: URL
    let displayPath: String
    let references: [EditorReference]
    let exactReferences: [EditorReference]
    let heuristicReferences: [EditorReference]

    var id: String { fileURL.path(percentEncoded: false) }
    var count: Int { references.count }

    init(fileURL: URL, displayPath: String, references: [EditorReference]) {
        self.fileURL = fileURL
        self.displayPath = displayPath
        self.references = references
        self.exactReferences = references.filter { !$0.isHeuristic }
        self.heuristicReferences = references.filter(\.isHeuristic)
    }

    static func group(_ references: [EditorReference], root: URL?) -> [ReferenceFileGroup] {
        guard !references.isEmpty else { return [] }
        let rootPath = root?.standardizedFileURL.path(percentEncoded: false)

        var byFile: [URL: [EditorReference]] = [:]
        for reference in references {
            byFile[reference.fileURL.standardizedFileURL, default: []].append(reference)
        }

        return byFile.map { url, items in
            ReferenceFileGroup(
                fileURL: url,
                displayPath: displayPath(for: url, rootPath: rootPath),
                references: items.sorted {
                    $0.range.location == $1.range.location
                        ? $0.range.length < $1.range.length
                        : $0.range.location < $1.range.location
                }
            )
        }.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    private static func displayPath(for url: URL, rootPath: String?) -> String {
        let path = url.path(percentEncoded: false)
        guard let rootPath, !rootPath.isEmpty, path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
