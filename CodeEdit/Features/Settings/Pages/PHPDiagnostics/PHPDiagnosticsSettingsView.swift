//
//  PHPDiagnosticsSettingsView.swift
//  CodeEdit
//
//  Settings ▸ PHP Diagnostics: code-quality rule configuration for the native PHP engine.
//

import SwiftUI

struct PHPDiagnosticsSettingsView: View {
    @AppSettings(\.phpDiagnostics.classLength)
    var classLength
    @AppSettings(\.phpDiagnostics.methodLength)
    var methodLength
    @AppSettings(\.phpDiagnostics.fileLength)
    var fileLength
    @AppSettings(\.phpDiagnostics.parameterCount)
    var parameterCount
    @AppSettings(\.phpDiagnostics.complexity)
    var complexity
    @AppSettings(\.phpDiagnostics.lineLength)
    var lineLength
    @AppSettings(\.phpDiagnostics.requireStrictTypes)
    var requireStrictTypes
    @AppSettings(\.phpDiagnostics.reportTodos)
    var reportTodos
    @AppSettings(\.phpDiagnostics.reportNaming)
    var reportNaming
    @AppSettings(\.phpDiagnostics.disabledRules)
    var disabledRules
    @AppSettings(\.phpDiagnostics.skipPatterns)
    var skipPatterns

    private static let rules: [(id: String, title: String)] = [
        ("php.length.class", "Class length"),
        ("php.length.method", "Method length"),
        ("php.length.file", "File length"),
        ("php.style.parameterCount", "Parameter count"),
        ("php.complexity", "Cyclomatic complexity"),
        ("php.style.lineLength", "Line length"),
        ("php.strictTypes", "Require strict types"),
        ("php.style.todo", "TODO/FIXME comments"),
        ("php.safety.looseComparison", "Loose comparison (== / !=)"),
        ("php.deadCode.unusedParameter", "Unused parameters"),
        ("php.naming.class", "Class naming (StudlyCaps)"),
        ("php.naming.method", "Method naming (camelCase)")
    ]

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Require 'declare(strict_types=1);'", isOn: $requireStrictTypes)
                Toggle("Report TODO / FIXME comments", isOn: $reportTodos)
                Toggle("Report PSR naming conventions", isOn: $reportNaming)
            } header: {
                Text("Code Quality")
                Text("Diagnostics for PHP files using the built-in engine.")
            }

            Section {
                Stepper("Class length: \(classLength) lines", value: $classLength, in: 50...1000, step: 10)
                Stepper("Method length: \(methodLength) lines", value: $methodLength, in: 10...500, step: 5)
                Stepper("File length: \(fileLength) lines", value: $fileLength, in: 100...5000, step: 50)
                Stepper("Parameter count: \(parameterCount)", value: $parameterCount, in: 1...20)
                Stepper("Complexity: \(complexity)", value: $complexity, in: 1...100)
                Stepper("Line length: \(lineLength) chars", value: $lineLength, in: 40...300, step: 10)
            } header: {
                Text("Thresholds")
            }

            Section {
                ForEach(Self.rules, id: \.id) { rule in
                    Toggle(rule.title, isOn: enabledBinding(rule.id))
                }
            } header: {
                Text("Rules")
                Text("Disable individual rules.")
            }

            Section {
                TextField("Skip paths", text: skipPatternsBinding, prompt: Text("/vendor/, .generated."))
                    .accessibilityLabel("Skip paths")
            } header: {
                Text("Skip Paths")
                Text("Comma-separated path substrings. Files matching any are not linted.")
            }
        }
    }

    /// Whether a rule is enabled (not in `disabledRules`).
    private func enabledBinding(_ ruleID: String) -> Binding<Bool> {
        Binding {
            !disabledRules.contains(ruleID)
        } set: { enabled in
            if enabled {
                disabledRules.removeAll { $0 == ruleID }
            } else if !disabledRules.contains(ruleID) {
                disabledRules.append(ruleID)
            }
        }
    }

    /// Comma-separated editing binding over the skip-patterns array.
    private var skipPatternsBinding: Binding<String> {
        Binding {
            skipPatterns.joined(separator: ", ")
        } set: { newValue in
            skipPatterns = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
