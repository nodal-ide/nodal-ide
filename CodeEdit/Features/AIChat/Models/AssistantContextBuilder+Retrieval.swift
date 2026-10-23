import Foundation

extension AssistantContextBuilder {
    static func retrievalItems(from result: AssistantRetrievalResult) -> [AssistantContextItem] {
        result.code.enumerated().map { index, excerpt in
            let fileName = (excerpt.relativePath as NSString).lastPathComponent
            let title = excerpt.startLine == excerpt.endLine
                ? "\(fileName):\(excerpt.startLine)"
                : "\(fileName):\(excerpt.startLine)–\(excerpt.endLine)"
            let redaction = SecretRedactor.redact(excerpt.text)
            return AssistantContextItem(
                id: "R\(index + 1)",
                kind: .retrievedCode,
                title: title,
                relativePath: excerpt.relativePath,
                lineRange: excerpt.startLine...excerpt.endLine,
                languageID: excerpt.languageID,
                text: redaction.text,
                redactionCount: redaction.count,
                warnings: redaction.replacements.isEmpty
                    ? []
                    : ["\(redaction.count) possible secret\(redaction.count == 1 ? "" : "s") redacted."]
            )
        }
    }

    static func knowledgeItems(from result: AssistantRetrievalResult) -> [AssistantContextItem] {
        result.knowledge.enumerated().map { index, excerpt in
            let redaction = SecretRedactor.redact(excerpt.text)
            return AssistantContextItem(
                id: "K\(index + 1)",
                kind: .knowledge,
                title: excerpt.title,
                relativePath: excerpt.pagePath,
                knowledgeSourceID: excerpt.sourceID,
                text: redaction.text,
                redactionCount: redaction.count,
                warnings: redaction.replacements.isEmpty
                    ? []
                    : ["\(redaction.count) possible secret\(redaction.count == 1 ? "" : "s") redacted."]
            )
        }
    }
}
