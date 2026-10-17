//
//  TestOutputParser.swift
//  CodeEdit
//
//  Parses test-runner output into results (TAP or JUnit XML).
//

import Foundation

enum TestOutputParser {
    static func parse(_ output: String) -> [TestResult] {
        let cleaned = strippingANSI(output)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            return parseJUnit(cleaned)
        }
        if isForgeOutput(trimmed) {
            return parseForge(cleaned)
        }
        return parseTAP(cleaned)
    }

    /// Removes ANSI CSI escape sequences (e.g. `\u{001B}[0;34m`) that colour terminal output.
    static func strippingANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Forge (php forge.php test)

    private static let forgeHeaders: Set<String> = [
        "Passed Tests:", "Failures:", "Skipped Tests:", "Incomplete Tests:",
        "Test Results:", "Metric Benchmarks:", "Slowest Tests:", "Test Durations:"
    ]

    private static func isForgeOutput(_ output: String) -> Bool {
        output.contains("Passed Tests:") || output.contains("Test Results:") || output.contains("\nFailures:")
    }

    static func parseForge(_ output: String) -> [TestResult] {
        var results: [TestResult] = []
        let lines = output.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            switch lines[index].trimmingCharacters(in: .whitespaces) {
            case "Passed Tests:":
                index = parseForgeTable(lines, from: index + 1, into: &results)
            case "Failures:":
                index = parseForgeBlocks(lines, from: index + 1, status: .failed, into: &results)
            case "Skipped Tests:":
                index = parseForgeBlocks(lines, from: index + 1, status: .skipped, into: &results)
            default:
                index += 1
            }
        }
        return results
    }

    private static func parseForgeTable(
        _ lines: [String],
        from start: Int,
        into results: inout [TestResult]
    ) -> Int {
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if columns.count >= 2, columns[0] != "Test" {
                    results.append(
                        TestResult(
                            suite: columns.count >= 2 ? columns[1] : "Tests",
                            name: columns[0],
                            status: .passed,
                            duration: columns.count >= 4 ? forgeDuration(columns[3]) : nil,
                            message: nil,
                            fileURL: nil,
                            line: nil
                        )
                    )
                }
                index += 1
            } else if line.isEmpty || line.hasPrefix("+") {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private static func parseForgeBlocks(
        _ lines: [String],
        from start: Int,
        status: TestResult.Status,
        into results: inout [TestResult]
    ) -> Int {
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard let (suite, name) = forgeClassMethod(line) else {
                if forgeHeaders.contains(line) { break }
                index += 1
                continue
            }
            var block: [String] = []
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if forgeHeaders.contains(next) || forgeClassMethod(next) != nil { break }
                block.append(next)
                index += 1
            }
            let details = forgeDetails(block, status: status)
            results.append(
                TestResult(
                    suite: suite,
                    name: name,
                    status: status,
                    duration: nil,
                    message: details.message,
                    fileURL: details.fileURL,
                    line: details.line
                )
            )
        }
        return index
    }

    private static func forgeClassMethod(_ line: String) -> (String, String)? {
        guard let separator = line.range(of: "::") else { return nil }
        let suite = String(line[..<separator.lowerBound])
        guard !suite.isEmpty,
              suite.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "\\" }) else {
            return nil
        }
        let method = line[separator.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return method.isEmpty ? nil : (suite, String(method))
    }

    private static func forgeDetails(_ block: [String], status: TestResult.Status) -> ForgeDetails {
        var messageLines = block
        var fileURL: URL?
        var lineNumber: Int?
        if status == .failed, let last = block.last, let (url, number) = forgeFileLine(last) {
            fileURL = url
            lineNumber = number
            messageLines = Array(block.dropLast())
        }
        let message = messageLines
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ForgeDetails(message: message.isEmpty ? nil : message, fileURL: fileURL, line: lineNumber)
    }

    private static func forgeFileLine(_ line: String) -> (URL, Int)? {
        guard let colon = line.lastIndex(of: ":") else { return nil }
        let numberPart = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let number = Int(numberPart) else { return nil }
        let path = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        guard path.contains("/") else { return nil }
        return (URL(filePath: path), number)
    }

    private static func forgeDuration(_ text: String) -> Double? {
        let value = text.replacingOccurrences(of: "ms", with: "").trimmingCharacters(in: .whitespaces)
        return Double(value).map { $0 / 1000 }
    }

    // MARK: - TAP

    static func parseTAP(_ output: String) -> [TestResult] {
        var results: [TestResult] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let failed: Bool
            let body: String
            if line.hasPrefix("not ok ") {
                failed = true
                body = String(line.dropFirst("not ok ".count))
            } else if line.hasPrefix("ok ") {
                failed = false
                body = String(line.dropFirst("ok ".count))
            } else {
                continue
            }

            var name = body
            // Strip a leading test number.
            if let space = name.firstIndex(of: " "), Int(name[name.startIndex..<space]) != nil {
                name = String(name[name.index(after: space)...])
            }

            var status: TestResult.Status = failed ? .failed : .passed
            var message: String?
            if let hash = name.range(of: " # ") {
                let directive = String(name[hash.upperBound...])
                name = String(name[..<hash.lowerBound])
                if directive.uppercased().contains("SKIP") {
                    status = .skipped
                } else if failed {
                    message = directive
                }
            }

            results.append(
                TestResult(
                    suite: "Tests",
                    name: name.trimmingCharacters(in: .whitespaces),
                    status: status,
                    duration: nil,
                    message: message,
                    fileURL: nil,
                    line: nil
                )
            )
        }
        return results
    }

    // MARK: - JUnit

    static func parseJUnit(_ output: String) -> [TestResult] {
        guard let data = output.data(using: .utf8) else { return [] }
        let parser = JUnitDelegate()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.results
    }
}

private struct ForgeDetails {
    var message: String?
    var fileURL: URL?
    var line: Int?
}

private final class JUnitDelegate: NSObject, XMLParserDelegate {
    var results: [TestResult] = []
    private var suiteName = ""
    private var currentName: String?
    private var currentTime: Double?
    private var failureMessage: String?
    private var status: TestResult.Status = .passed
    private var failureText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "testsuite":
            suiteName = attributeDict["name"] ?? ""
        case "testcase":
            currentName = attributeDict["name"] ?? "test"
            currentTime = attributeDict["time"].flatMap(Double.init)
            failureMessage = nil
            status = .passed
        case "failure":
            status = .failed
            failureMessage = attributeDict["message"]
        case "error":
            status = .error
            failureMessage = attributeDict["message"]
        case "skipped":
            status = .skipped
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        failureText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "testcase", let name = currentName else { return }
        let message = failureMessage ?? (failureText.isEmpty ? nil : failureText)
        results.append(
            TestResult(
                suite: suiteName.isEmpty ? "Tests" : suiteName,
                name: name,
                status: status,
                duration: currentTime,
                message: message?.trimmingCharacters(in: .whitespacesAndNewlines),
                fileURL: nil,
                line: nil
            )
        )
        currentName = nil
        failureText = ""
    }
}
