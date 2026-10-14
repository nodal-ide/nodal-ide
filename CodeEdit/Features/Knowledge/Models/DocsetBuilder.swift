//
//  DocsetBuilder.swift
//  CodeEdit
//
//  Builds a knowledge source from a Dash/Zeal `.docset` bundle.
//

import Foundation

/// Reads a `.docset` (Dash/Zeal format) into a knowledge source.
///
/// A docset is `<Name>.docset/Contents/{Info.plist,Resources/Documents/*.html}`. Full-text search
/// indexes in the docset are ignored; instead a table of contents is built by walking the HTML files.
enum DocsetBuilder {
    struct Result {
        let title: String
        let documents: URL
        let index: KnowledgeIndex
    }

    static func load(_ docsetURL: URL) -> Result? {
        let documents = docsetURL.appending(path: "Contents/Resources/Documents")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: documents.path(percentEncoded: false)) else { return nil }

        let info = readInfoPlist(docsetURL)
        let docsetTitle = (info["CFBundleName"] as? String)
            ?? (info["CFBundleDisplayName"] as? String)
            ?? docsetURL.deletingPathExtension().lastPathComponent

        var files: [String] = []
        let documentsPath = documents.path(percentEncoded: false)
        if let enumerator = fileManager.enumerator(
            at: documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "html" || ext == "htm" else { continue }
                let path = url.path(percentEncoded: false)
                guard path.hasPrefix(documentsPath + "/") else { continue }
                files.append(String(path.dropFirst(documentsPath.count + 1)))
                if files.count >= 1000 { break }
            }
        }
        guard !files.isEmpty else { return nil }
        files.sort()

        let toc = files.map { path in
            KnowledgeIndex.TOCItem(
                title: title(of: documents.appending(path: path), fallback: (path as NSString).deletingPathExtension),
                path: path,
                children: nil
            )
        }

        let dashIndex = info["dashIndexFilePath"] as? String
        var home = "index.html"
        if let dashIndex, files.contains(dashIndex) {
            home = dashIndex
        } else if !files.contains(home) {
            home = files[0]
        }

        let index = KnowledgeIndex(title: docsetTitle, subtitle: "Docset", home: home, keywords: nil, toc: toc)
        return Result(title: docsetTitle, documents: documents, index: index)
    }

    private static func readInfoPlist(_ docsetURL: URL) -> [String: Any] {
        let url = docsetURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    /// Reads a page's `<title>`, falling back to the file name.
    private static func title(of url: URL, fallback: String) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data.prefix(4096), encoding: .utf8),
              let start = text.range(of: "<title>", options: .caseInsensitive),
              let end = text.range(of: "</title>", options: .caseInsensitive, range: start.upperBound..<text.endIndex) else {
            return (fallback as NSString).lastPathComponent
        }
        let title = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (fallback as NSString).lastPathComponent : title
    }
}
