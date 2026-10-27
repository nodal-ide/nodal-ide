import Foundation

/// Splits source text into the lowercased search terms that feed the retrieval index.
///
/// Tokenization runs for every chunk of every indexed file and for every query, so the scan is
/// single-pass over the text with no regular expressions and no per-token `CharacterSet` work: the
/// previous implementation compiled an `NSRegularExpression` for each identifier and unioned
/// `CharacterSet`s for each produced term, which dominated the whole workspace index build.
enum AssistantRetrievalTokenizer {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "can", "do", "does", "for",
        "from", "how", "i", "if", "in", "is", "it", "of", "on", "or", "should", "that",
        "the", "this", "to", "was", "we", "what", "when", "where", "which", "why", "with",
        "would", "you"
    ]

    private static let alphanumerics = CharacterSet.letters.union(.decimalDigits)

    static func terms(in text: String) -> [String] {
        var result: [String] = []
        var identifier: [UInt8] = []
        identifier.reserveCapacity(64)

        func flushIdentifier() {
            guard !identifier.isEmpty else { return }
            appendTerms(from: identifier, into: &result)
            identifier.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            guard scalar.isASCII, isIdentifier(UInt8(scalar.value)) else {
                flushIdentifier()
                continue
            }
            identifier.append(UInt8(scalar.value))
        }
        flushIdentifier()
        return result
    }

    static func termFrequencies(in text: String) -> [String: Int] {
        var frequencies: [String: Int] = [:]
        for term in terms(in: text) {
            frequencies[term, default: 0] += 1
        }
        return frequencies
    }

    static func weightedTerms(in text: String, weight: Double) -> [String: Double] {
        var result: [String: Double] = [:]
        for term in terms(in: text) {
            result[term, default: 0] += weight
        }
        return result
    }

    // MARK: - Identifier splitting

    /// Splits one `[A-Za-z0-9_]+` run into words, mirroring the previous `_`-split followed by
    /// `([A-Z]+)([A-Z][a-z])` and `([a-z0-9])([A-Z])` passes: underscores and camel/acronym
    /// boundaries start a new word, digits only end one.
    private static func appendTerms(from identifier: [UInt8], into result: inout [String]) {
        var piece = ""
        var previousByte: UInt8?

        func flush() {
            appendTerm(piece, into: &result)
            piece = ""
            previousByte = nil
        }

        var index = 0
        while index < identifier.count {
            let byte = identifier[index]
            if byte == 0x5F {
                flush()
                index += 1
                continue
            }
            if let previous = previousByte {
                let startsNewWord = isUppercase(byte)
                    && (
                        isLowercaseOrDigit(previous)
                            || (
                                isUppercase(previous)
                                    && index + 1 < identifier.count
                                    && isLowercase(identifier[index + 1])
                            )
                    )
                if startsNewWord { flush() }
            }
            piece.unicodeScalars.append(Unicode.Scalar(byte))
            previousByte = byte
            index += 1
        }
        flush()
    }

    private static func appendTerm(_ piece: String, into result: inout [String]) {
        guard !piece.isEmpty else { return }
        let term = piece.lowercased()
        guard term.count >= 2,
              !stopWords.contains(term),
              term.rangeOfCharacter(from: alphanumerics) != nil
        else { return }
        result.append(term)
    }

    // MARK: - ASCII helpers

    private static func isIdentifier(_ byte: UInt8) -> Bool {
        isUppercase(byte) || isLowercase(byte) || isDigit(byte) || byte == 0x5F
    }

    private static func isUppercase(_ byte: UInt8) -> Bool { byte >= 0x41 && byte <= 0x5A }

    private static func isLowercase(_ byte: UInt8) -> Bool { byte >= 0x61 && byte <= 0x7A }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    private static func isLowercaseOrDigit(_ byte: UInt8) -> Bool { isLowercase(byte) || isDigit(byte) }
}
