//
//  KnowledgeRenderer.swift
//  CodeEdit
//
//  A small Markdown → HTML renderer for knowledge pages. No external dependency.
//

import Foundation

enum KnowledgeRenderer {
    /// Renders a full HTML document for a page.
    static func html(forPath path: String, source: KnowledgeSource) -> String {
        guard let markdown = source.content(for: path) else {
            return document(
                title: "Not found",
                body: "<h1>Page not found</h1><p><code>\(escape(path))</code>",
                source: source
            )
        }
        let title = title(forPath: path, source: source)
        // HTML pages (e.g. imported docsets) are passed through untouched.
        if isHTMLPage(path) {
            return document(title: title, body: markdown, source: source)
        }
        return document(title: title, body: renderMarkdown(markdown, currentPath: path), source: source)
    }

    static func isHTMLPage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    private static func title(forPath path: String, source: KnowledgeSource) -> String {
        source.pages.first { $0.path.map(KnowledgeSource.normalize) == KnowledgeSource.normalize(path) }?.title
            ?? source.title
    }

    // MARK: - Markdown

    static func renderMarkdown(_ text: String, currentPath: String) -> String {
        var html = ""
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]

            // Fenced code block.
            if line.hasPrefix("```") {
                html += fencedCode(lines: lines, index: &index)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Headings.
            if let heading = heading(trimmed) {
                let anchor = slug(heading.text)
                html += "<h\(heading.level) id=\"\(anchor)\">\(inline(heading.text, currentPath: currentPath))"
                    + "</h\(heading.level)>\n"
                index += 1
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html += "<hr>\n"
                index += 1
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                html += blockquote(lines: lines, index: &index, currentPath: currentPath)
                continue
            }

            // Table.
            if trimmed.hasPrefix("|"), index + 1 < lines.count,
               lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|"),
               lines[index + 1].contains("-") {
                html += table(lines: lines, index: &index, currentPath: currentPath)
                continue
            }

            // Lists.
            if isUnorderedListItem(trimmed) || isOrderedListItem(trimmed) {
                html += list(lines: lines, index: &index, currentPath: currentPath)
                continue
            }

            // Blank line.
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Paragraph.
            html += paragraph(lines: lines, index: &index, currentPath: currentPath)
        }

        return html
    }

    private static func fencedCode(lines: [String], index: inout Int) -> String {
        let language = String(lines[index].dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var code: [String] = []
        index += 1
        while index < lines.count, !lines[index].hasPrefix("```") {
            code.append(lines[index])
            index += 1
        }
        index += 1 // closing fence
        let classAttribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
        return "<pre><code\(classAttribute)>\(escape(code.joined(separator: "\n")))</code></pre>\n"
    }

    private static func blockquote(lines: [String], index: inout Int, currentPath: String) -> String {
        var quote: [String] = []
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst())
                .trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return "<blockquote><p>"
            + inline(quote.joined(separator: " "), currentPath: currentPath)
            + "</p></blockquote>\n"
    }

    private static func paragraph(lines: [String], index: inout Int, currentPath: String) -> String {
        var paragraph: [String] = []
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            if candidate.isEmpty || heading(candidate) != nil || candidate.hasPrefix("```")
                || candidate.hasPrefix(">") || candidate.hasPrefix("|")
                || isUnorderedListItem(candidate) || isOrderedListItem(candidate) {
                break
            }
            paragraph.append(candidate)
            index += 1
        }
        return "<p>\(inline(paragraph.joined(separator: " "), currentPath: currentPath))</p>\n"
    }

    // MARK: - Blocks

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        return (level, String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        guard let dot = line.firstIndex(of: ".") else { return false }
        return line[line.startIndex..<dot].allSatisfy(\.isNumber) && line.index(after: dot) < line.endIndex
            && line[line.index(after: dot)] == " "
    }

    private static func list(lines: [String], index: inout Int, currentPath: String) -> String {
        let ordered = isOrderedListItem(lines[index].trimmingCharacters(in: .whitespaces))
        var items: [String] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard ordered ? isOrderedListItem(line) : isUnorderedListItem(line) else { break }
            items.append(String(line.dropFirst(2)))
            index += 1
        }
        let tag = ordered ? "ol" : "ul"
        let body = items.map { "<li>\(inline($0, currentPath: currentPath))</li>" }.joined()
        return "<\(tag)>\(body)</\(tag)>\n"
    }

    private static func table(lines: [String], index: inout Int, currentPath: String) -> String {
        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let header = cells(lines[index])
        index += 2 // header + separator
        var html = "<table><thead><tr>"
        html += header.map { "<th>\(inline($0, currentPath: currentPath))</th>" }.joined()
        html += "</tr></thead><tbody>"
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            let row = cells(lines[index])
            html += "<tr>" + row.map { "<td>\(inline($0, currentPath: currentPath))</td>" }.joined() + "</tr>"
            index += 1
        }
        html += "</tbody></table>\n"
        return html
    }

    // MARK: - Inline

    private static func inline(_ text: String, currentPath: String) -> String {
        var result = escape(text)

        // Images.
        result = replacing(result, pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") { _, groups in
            let alt = groups[0]
            let target = resolveLink(groups[1], from: currentPath).link
            return "<img src=\"\(target)\" alt=\"\(alt)\">"
        }

        // Links.
        result = replacing(result, pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") { _, groups in
            let resolution = resolveLink(groups[1], from: currentPath)
            return "<a href=\"\(resolution.link)\">\(groups[0])</a>"
        }

        // Inline code.
        result = replacing(result, pattern: "`([^`]+)`") { _, groups in
            "<code>\(groups[0])</code>"
        }

        // Bold, then italic.
        result = replacing(result, pattern: "\\*\\*([^*]+)\\*\\*") { _, groups in "<strong>\(groups[0])</strong>" }
        result = replacing(result, pattern: "\\*([^*]+)\\*") { _, groups in "<em>\(groups[0])</em>" }

        return result
    }

    // MARK: - Links

    /// Resolves a Markdown link target into an href and whether it is external.
    static func resolveLink(_ target: String, from currentPath: String) -> (link: String, external: Bool) {
        if target.contains("://") || target.hasPrefix("mailto:") || target.hasPrefix("//") {
            return (target, true)
        }

        var fragment = ""
        var path = target
        if let hash = target.firstIndex(of: "#") {
            fragment = String(target[target.index(after: hash)...])
            path = String(target[..<hash])
        }
        if path.isEmpty {
            return (fragment.isEmpty ? "#" : "#\(fragment)", false)
        }

        let resolved = resolvePath(path, from: currentPath)
        let encoded = resolved.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolved
        var link = "ce-knowledge:///\(encoded)"
        if !fragment.isEmpty {
            link += "#\(fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment)"
        }
        return (link, false)
    }

    private static func resolvePath(_ path: String, from currentPath: String) -> String {
        if path.hasPrefix("/") {
            return normalizePath(String(path.dropFirst()))
        }
        let directory = (currentPath as NSString).deletingLastPathComponent
        let combined = directory.isEmpty ? path : directory + "/" + path
        return normalizePath(combined)
    }

    static func normalizePath(_ path: String) -> String {
        var components: [String] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    // MARK: - Helpers

    private static func replacing(
        _ string: String,
        pattern: String,
        transform: ([String], [String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        var result = ""
        var lastIndex = string.startIndex
        let nsString = string as NSString
        regex.enumerateMatches(in: string, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            guard let match else { return }
            let full = Range(match.range, in: string)!
            result += string[lastIndex..<full.lowerBound]
            var groups: [String] = []
            for groupIndex in 1..<match.numberOfRanges {
                let range = match.range(at: groupIndex)
                groups.append(range.location == NSNotFound ? "" : nsString.substring(with: range))
            }
            result += transform(groups, groups)
            lastIndex = full.upperBound
        }
        result += string[lastIndex...]
        return result
    }

    private static func slug(_ text: String) -> String {
        text.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

}

// MARK: - Document

extension KnowledgeRenderer {
    private static func document(title: String, body: String, source: KnowledgeSource) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article>
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static let css = """
    :root { color-scheme: light dark; }
    body {
        font: -apple-system-body;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        margin: 0; padding: 24px 28px 64px;
        color: -apple-system-label;
        line-height: 1.55;
    }
    article { max-width: 720px; margin: 0 auto; }
    h1, h2, h3, h4 { line-height: 1.25; margin: 1.4em 0 0.5em; }
    h1 {
        font-size: 1.9em;
        border-bottom: 1px solid color-mix(in srgb, currentColor 15%, transparent);
        padding-bottom: .3em;
    }
    h2 { font-size: 1.4em; }
    a { color: -apple-system-control-accent; text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
        font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .9em;
        background: color-mix(in srgb, currentColor 8%, transparent);
        padding: .12em .35em; border-radius: 4px;
    }
    pre {
        background: color-mix(in srgb, currentColor 6%, transparent);
        padding: 12px 14px; border-radius: 8px; overflow-x: auto;
    }
    pre code { background: none; padding: 0; }
    blockquote {
        margin: 1em 0; padding: .2em 1em; color: -apple-system-secondary-label;
        border-left: 3px solid color-mix(in srgb, currentColor 20%, transparent);
    }
    table { border-collapse: collapse; width: 100%; margin: 1em 0; }
    th, td { text-align: left; padding: 6px 10px; border: 1px solid color-mix(in srgb, currentColor 15%, transparent); }
    th { background: color-mix(in srgb, currentColor 5%, transparent); }
    hr { border: none; border-top: 1px solid color-mix(in srgb, currentColor 15%, transparent); margin: 2em 0; }
    img { max-width: 100%; }
    mark.kh { background: rgba(255, 214, 0, 0.45); border-radius: 2px; }
    """
}
