import Foundation
import Testing
@testable import CodeEdit

struct LocalDomainSettingsDraftTests {
    @Test
    func applyingTrimsAndNormalizesValues() {
        var draft = LocalDomainSettingsDraft()
        draft.domain = "  MySite  "
        draft.documentRoot = " public/ "
        draft.entryFile = " index.php "
        draft.proxyPort = " 8080 "
        draft.proxyStartCommand = " npm run dev "
        draft.proxyWorkingDirectory = " frontend "

        let site = draft.applying(to: LocalSiteSettings())

        #expect(site.domain == "mysite.localhost")
        #expect(site.documentRoot == "public/")
        #expect(site.entryFile == "index.php")
        #expect(site.proxy.port == 8080)
        #expect(site.proxy.startCommand == "npm run dev")
        #expect(site.proxy.workingDirectory == "frontend")
    }

    @Test
    func applyingKeepsRawInvalidValuesForCorrection() {
        var draft = LocalDomainSettingsDraft()
        draft.domain = "bad_domain"
        draft.entryFile = ""
        draft.proxyPort = "not-a-port"

        let site = draft.applying(to: LocalSiteSettings())

        #expect(site.domain == "bad_domain")
        #expect(site.entryFile.isEmpty)
        #expect(site.proxy.port == 9000)
    }

    @Test
    func emptyDomainIsOnlyAnIssueWhenEnabled() {
        var site = LocalSiteSettings()
        let draft = LocalDomainSettingsDraft()

        site.enabled = false
        #expect(draft.issues(for: site, workspaceURL: nil).isEmpty)

        site.enabled = true
        let issue = draft.issues(for: site, workspaceURL: nil).first
        #expect(issue?.field == .domain)
        #expect(issue?.message == "Enter a local domain.")
    }

    @Test
    func invalidDomainExplainsTheProblem() {
        var draft = LocalDomainSettingsDraft()
        draft.domain = "Bad_Domain"

        let issue = draft.issues(for: LocalSiteSettings(), workspaceURL: nil).first

        #expect(issue?.field == .domain)
        #expect(issue?.message == "Use only lowercase letters, numbers, and hyphens.")
    }

    @Test
    func documentRootMustBeAnExistingRelativeDirectory() throws {
        try withTempDir { root in
            try FileManager.default.createDirectory(
                at: root.appending(path: "public", directoryHint: .isDirectory),
                withIntermediateDirectories: false
            )
            var site = LocalSiteSettings()
            site.handler = .staticFiles
            var draft = LocalDomainSettingsDraft()

            #expect(draft.issues(for: site, workspaceURL: root).isEmpty)

            draft.documentRoot = "public"
            #expect(draft.issues(for: site, workspaceURL: root).isEmpty)

            draft.documentRoot = "missing"
            let missing = draft.issues(for: site, workspaceURL: root).first
            #expect(missing?.field == .documentRoot)
            #expect(missing?.message.contains("does not exist") == true)

            for path in ["/tmp", "~/Sites", "../escape"] {
                draft.documentRoot = path
                let outside = draft.issues(for: site, workspaceURL: root).first
                #expect(outside?.field == .documentRoot)
                #expect(outside?.message == LocalSiteError.documentRootOutsideWorkspace.localizedDescription)
            }
        }
    }

    @Test
    func entryFileIsCheckedForSyntaxAndExistenceInFrontControllerMode() throws {
        try withTempDir { root in
            let publicDir = root.appending(path: "public", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: publicDir, withIntermediateDirectories: false)
            try Data().write(to: publicDir.appending(path: "index.php"))

            var site = LocalSiteSettings()
            site.handler = .phpFPM
            site.routing = .frontController
            var draft = LocalDomainSettingsDraft()
            draft.documentRoot = "public"

            #expect(draft.issues(for: site, workspaceURL: root).isEmpty)

            draft.entryFile = "missing.php"
            let missing = draft.issues(for: site, workspaceURL: root).first { $0.field == .entryFile }
            #expect(missing?.message == LocalSiteError.entryFileMissing("missing.php").localizedDescription)

            draft.entryFile = "index.txt"
            let syntax = draft.issues(for: site, workspaceURL: root).first { $0.field == .entryFile }
            #expect(syntax?.message.contains(".php") == true)

            site.routing = .directory
            draft.entryFile = "missing.php"
            #expect(!draft.issues(for: site, workspaceURL: root).contains { $0.field == .entryFile })

            draft.entryFile = ""
            let empty = draft.issues(for: site, workspaceURL: root).first { $0.field == .entryFile }
            #expect(empty?.message == "Enter an entry file, for example index.php.")
        }
    }

    @Test
    func proxyPortMustBeInRangeAndOnlyMattersForTheProxyHandler() {
        var site = LocalSiteSettings()
        site.handler = .proxy
        var draft = LocalDomainSettingsDraft()

        for value in ["0", "70000", "not-a-port", ""] {
            draft.proxyPort = value
            let issue = draft.issues(for: site, workspaceURL: nil).first { $0.field == .port }
            #expect(issue != nil, "expected an issue for \(value.debugDescription)")
        }

        draft.proxyPort = "9000"
        #expect(draft.issues(for: site, workspaceURL: nil).isEmpty)

        site.handler = .phpFPM
        draft.proxyPort = "not-a-port"
        #expect(!draft.issues(for: site, workspaceURL: nil).contains { $0.field == .port })
    }

    @Test
    func pinnedPHPMustBeAvailableWithFPM() {
        var site = LocalSiteSettings()
        site.handler = .phpFPM
        site.phpVersion = "8.3.6"
        let draft = LocalDomainSettingsDraft()

        let unavailable = draft.issues(
            for: site,
            workspaceURL: nil,
            availablePHPVersions: ["8.4.12"]
        )
        let issue = unavailable.first { $0.field == .runtime }
        #expect(issue?.message.contains("8.3.6") == true)

        #expect(draft.issues(
            for: site,
            workspaceURL: nil,
            availablePHPVersions: ["8.3.6"]
        ).isEmpty)

        #expect(draft.issues(for: site, workspaceURL: nil).isEmpty)

        site.phpVersion = nil
        #expect(draft.issues(
            for: site,
            workspaceURL: nil,
            availablePHPVersions: ["8.4.12"]
        ).isEmpty)
    }
}
