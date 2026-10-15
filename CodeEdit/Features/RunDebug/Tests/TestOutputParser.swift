//
//  TestOutputParser.swift
//  CodeEdit
//
//  Parses test-runner output into results (TAP or JUnit XML).
//

import Foundation

enum TestOutputParser {
    static func parse(_ output: String) -> [TestResult] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            return parseJUnit(output)
        }
        return parseTAP(output)
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
