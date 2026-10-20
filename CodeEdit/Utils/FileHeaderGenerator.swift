import Foundation
import CodeEditLanguages

enum FileHeaderGenerator {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    static func generateHeader(
        for fileURL: URL,
        organization: String,
        author: String,
        date: Date = Date()
    ) -> String {
        let fileName = fileURL.lastPathComponent
        let dateString = dateFormatter.string(from: date)
        let resolvedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? NSFullUserName()
            : author.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentName = fileURL.deletingLastPathComponent().lastPathComponent
        let resolvedOrg = organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (parentName.isEmpty ? "CodeEdit" : parentName)
            : organization.trimmingCharacters(in: .whitespacesAndNewlines)

        let language = CodeLanguage.detectLanguageFrom(url: fileURL)
        let isPHP = language.id == .php || fileURL.pathExtension.lowercased() == "php"
        let prefix = isPHP ? "<?php\n\n" : ""
        let lineComment = language.lineCommentString

        if !lineComment.isEmpty {
            return """
            \(prefix)\(lineComment)
            \(lineComment)  \(fileName)
            \(lineComment)  \(resolvedOrg)
            \(lineComment)
            \(lineComment)  Created by \(resolvedAuthor) on \(dateString).
            \(lineComment)

            """
        }

        let (openRange, closeRange) = language.rangeCommentStrings
        if !openRange.isEmpty && !closeRange.isEmpty {
            return """
            \(openRange)
              \(fileName)
              \(resolvedOrg)

              Created by \(resolvedAuthor) on \(dateString).
            \(closeRange)

            """
        }

        return """
        //
        //  \(fileName)
        //  \(resolvedOrg)
        //
        //  Created by \(resolvedAuthor) on \(dateString).
        //

        """
    }

    static func generateHeaderData(
        for fileURL: URL,
        organization: String,
        author: String,
        date: Date = Date()
    ) -> Data? {
        let headerText = generateHeader(
            for: fileURL,
            organization: organization,
            author: author,
            date: date
        )
        return headerText.data(using: .utf8)
    }
}
