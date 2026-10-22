@testable import CodeEdit
import Testing
import Foundation
import CodeEditLanguages
import CodeEditSourceEditor

@Suite
struct LanguageZoneAttributionTests {
    @MainActor
    @Test
    func diagnosticsStoreTreatsZoneAsPartOfDiagnosticIdentity() {
        let store = DiagnosticsStore.shared
        let file = URL(fileURLWithPath: "/tmp/language-zone-attribution.php")
        let range = NSRange(location: 12, length: 4)
        let php = LanguageZoneContext(languageID: LanguageID(rawValue: "php"), sourceKey: "root", range: range)
        let html = LanguageZoneContext(
            languageID: LanguageID(rawValue: "html"),
            parentLanguageID: LanguageID(rawValue: "php"),
            sourceKey: "php-html",
            depth: 1,
            range: range
        )
        let diagnostic = EditorDiagnostic(range: range, severity: .warning, message: "Issue", languageContext: php)

        store.update(file: file, diagnostics: [diagnostic])
        let initialRevision = store.revision
        store.update(
            file: file,
            diagnostics: [EditorDiagnostic(range: range, severity: .warning, message: "Issue", languageContext: html)]
        )

        #expect(store.revision == initialRevision + 1)
        #expect(store.problems(in: file.deletingLastPathComponent()).first(where: { $0.fileURL == file })?.languageContext == html)
        store.clear(file: file)
    }
}
