//
//  GitRepositorySource.swift
//  CodeEdit
//
//  Validation and path handling shared by Git-backed extension sources.
//

import Foundation

enum GitRepositoryLocation {
    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let scp = scpStyleComponents(trimmed) {
            var components = URLComponents()
            components.scheme = "ssh"
            components.user = scp.user
            components.host = scp.host
            components.path = "/" + scp.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            return components.url
        }
        return URL(string: trimmed)
    }

    static func isValid(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.password == nil,
              components.query == nil,
              components.fragment == nil else { return false }

        if url.isFileURL {
            return components.user == nil
                && (components.host ?? "").isEmpty
                && !components.path.isEmpty
        }

        guard let scheme = components.scheme?.lowercased(), components.host != nil else {
            return false
        }
        switch scheme {
        case "https":
            return components.user == nil
        case "ssh":
            return true
        default:
            return false
        }
    }

    static func normalizedRevision(_ revision: String?) -> String? {
        guard let revision else { return nil }
        let trimmed = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isValidRevision(_ revision: String?) -> Bool {
        guard let revision = normalizedRevision(revision) else { return true }
        guard revision.utf8.count <= 200,
              revision.first != "-",
              revision.last != "/",
              !revision.contains(".."),
              !revision.contains("//"),
              !revision.hasSuffix(".lock") else {
            return false
        }
        guard revision.utf8.allSatisfy(Self.isRevisionByte) else { return false }
        return revision.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".")
        }
    }

    static func packagePath(from url: URL) -> String? {
        guard url.scheme == nil, url.host == nil else { return nil }
        let path = url.path(percentEncoded: false)
        guard !path.isEmpty,
              path.utf8.count <= 1_024,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !path.contains("\\"),
              !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return path
    }

    private static func isRevisionByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
            || (65...90).contains(byte)
            || (97...122).contains(byte)
            || byte == 43
            || byte == 45
            || byte == 46
            || byte == 47
            || byte == 95
    }

    private static func scpStyleComponents(
        _ input: String
    ) -> (user: String, host: String, path: String)? {
        guard !input.contains("://"),
              let at = input.firstIndex(of: "@") else { return nil }
        let afterAt = input.index(after: at)
        guard let colon = input[afterAt...].firstIndex(of: ":") else { return nil }
        let user = String(input[..<at])
        let host = String(input[afterAt..<colon])
        let path = String(input[input.index(after: colon)...])
        guard !user.isEmpty,
              !host.isEmpty,
              !path.isEmpty,
              !user.contains("/"),
              !host.contains("/"),
              !host.contains(":") else {
            return nil
        }
        return (user, host, path)
    }
}
