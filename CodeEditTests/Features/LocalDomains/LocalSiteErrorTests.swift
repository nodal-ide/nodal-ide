import Testing
@testable import CodeEdit

struct LocalSiteErrorTests {
    @Test
    func mapsErrorsToRecoveryActions() {
        #expect(LocalSiteError.invalidDomain(.empty).recoveryAction == .editDomain)
        #expect(LocalSiteError.domainInUse("my-app.localhost").recoveryAction == .editDomain)
        #expect(LocalSiteError.documentRootMissing("public").recoveryAction == .editDocumentRoot)
        #expect(LocalSiteError.documentRootOutsideWorkspace.recoveryAction == .editDocumentRoot)
        #expect(LocalSiteError.entryFileMissing("index.php").recoveryAction == .editEntryFile)
        #expect(LocalSiteError.phpFPMUnavailable("8.4").recoveryAction == .installPHP)
        #expect(LocalSiteError.nginxUnavailable.recoveryAction == .installNginx)
        #expect(LocalSiteError.certificateUntrusted.recoveryAction == .trustCertificate)
        #expect(LocalSiteError.portInUse(8080).recoveryAction == .changePort)
        #expect(LocalSiteError.upstreamNotReady(port: 9000, output: "").recoveryAction == .viewLogs)
        #expect(LocalSiteError.processFailed("failed").recoveryAction == .viewLogs)
    }

    @Test
    func providesDescriptionsAndSuggestions() {
        let error = LocalSiteError.portInUse(8080)

        #expect(error.errorDescription == "Port 8080 is already in use.")
        #expect(error.recoverySuggestion == "Stop the other service or choose another port.")
    }

    @Test
    func upstreamFailureIncludesTheOutputTail() {
        let error = LocalSiteError.upstreamNotReady(port: 9000, output: "Error: EADDRINUSE")

        #expect(error.errorDescription?.contains("port 9000") == true)
        #expect(error.errorDescription?.contains("Error: EADDRINUSE") == true)
        #expect(error.recoverySuggestion?.contains("start command") == true)
    }

    @Test
    func validationIssueHasStableIdentity() {
        let issue = SiteValidationIssue(
            field: .domain,
            message: "Enter a local domain.",
            recoveryAction: .editDomain
        )

        #expect(issue.id == "domain:Enter a local domain.")
    }
}
