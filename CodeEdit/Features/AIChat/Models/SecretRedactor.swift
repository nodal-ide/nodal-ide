import Foundation

struct AssistantRedactionResult: Equatable, Sendable {
    let text: String
    let replacements: [String]

    var count: Int {
        replacements.count
    }
}

enum SecretRedactor {
    private struct Rule {
        let pattern: String
        let replacement: String
        let label: String
        let options: NSRegularExpression.Options
    }

    private struct CompiledRule {
        let expression: NSRegularExpression
        let replacement: String
        let label: String
    }

    private static let rules: [Rule] = [
        Rule(
            pattern: #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#,
            replacement: "[REDACTED PRIVATE KEY]",
            label: "private key",
            options: [.dotMatchesLineSeparators]
        ),
        Rule(
            pattern: #"(?i)\b(Bearer\s+)([A-Za-z0-9._~+/=-]{8,})"#,
            replacement: "$1[REDACTED]",
            label: "bearer token",
            options: [.caseInsensitive]
        ),
        Rule(
            pattern: #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
            replacement: "[REDACTED]",
            label: "API key",
            options: []
        ),
        Rule(
            pattern: #"\b(gh[pousr]_[A-Za-z0-9]{20,})\b"#,
            replacement: "[REDACTED]",
            label: "GitHub token",
            options: []
        ),
        Rule(
            pattern: #"\b(AKIA[0-9A-Z]{16})\b"#,
            replacement: "[REDACTED]",
            label: "AWS access key",
            options: []
        ),
        Rule(
            pattern: #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#,
            replacement: "[REDACTED]",
            label: "Slack token",
            options: []
        ),
        Rule(
            pattern: #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
            replacement: "[REDACTED]",
            label: "JSON web token",
            options: []
        ),
        Rule(
            pattern: #"(?i)\b(https?://[^/\s:@]+:)([^@\s/]+)(@)"#,
            replacement: "$1[REDACTED]$3",
            label: "URL password",
            options: [.caseInsensitive]
        ),
        Rule(
            pattern: #"(?i)\b(api[_-]?key|secret|password|passwd|access[_-]?token|auth[_-]?token|"#
                + #"client[_-]?secret|token)\b(\s*[:=]\s*)(["']?)([^"'\s,;]{6,})\3"#,
            replacement: "$1$2$3[REDACTED]$3",
            label: "credential assignment",
            options: [.caseInsensitive]
        )
    ]

    private static let compiledRules: [CompiledRule] = rules.compactMap { rule in
        guard let expression = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
            return nil
        }
        return CompiledRule(expression: expression, replacement: rule.replacement, label: rule.label)
    }

    private static let secretExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "jks", "keystore", "mobileprovision", "cer", "crt"
    ]

    private static let secretFileNames: Set<String> = [
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "credentials", "credentials.json",
        ".netrc", "_netrc", "secrets", "secrets.json", "secrets.yml", "secrets.yaml",
        "keychain", "keychain.json", ".git-credentials"
    ]

    static func redact(_ text: String) -> AssistantRedactionResult {
        var result = text
        var replacements: [String] = []

        for rule in compiledRules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = rule.expression.matches(in: result, range: range)
            guard !matches.isEmpty else { continue }

            for _ in matches {
                replacements.append(rule.label)
            }
            result = rule.expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )
        }

        return AssistantRedactionResult(text: result, replacements: replacements)
    }

    static func isSecretPath(_ path: String) -> Bool {
        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
            .split(separator: "/")
            .map(String.init)

        guard let fileName = components.last, !fileName.isEmpty else { return false }

        if components.contains(".ssh")
            || components.contains(".gnupg")
            || components.contains(".aws")
            || components.contains("secrets")
            || components.contains(".secrets")
            || components.contains("credentials") {
            return true
        }
        if fileName.hasPrefix(".env") {
            return true
        }
        if secretFileNames.contains(fileName) {
            return true
        }
        if fileName.hasPrefix("id_") && fileName.dropFirst(3).contains("rsa") {
            return true
        }
        if fileName.contains("credential") || fileName.contains("secret") {
            return true
        }
        if fileName.contains("keychain") {
            return true
        }

        let fileExtension = (fileName as NSString).pathExtension
        return !fileExtension.isEmpty && secretExtensions.contains(fileExtension)
    }

    static func warnings(forSecretPath path: String) -> [String] {
        [
            "\(path) looks like it may contain secrets. Review the context preview before sending."
        ]
    }
}
