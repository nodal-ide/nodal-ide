import Foundation
import Testing
@testable import CodeEdit

struct SecurityCertificateInspectorTests {
    @Test
    func readsExpiryAndDNSNamesFromAPEMCertificate() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "fixture.pem")
            try Data(Self.fixturePEM.utf8).write(to: url)

            let details = try SecurityCertificateInspector().details(forCertificateAt: url)

            #expect(details.domains.contains("fixture.localhost"))
            #expect(details.domains.contains("api.localhost"))
            #expect(details.notAfter == Self.expectedExpiry)
        }
    }

    @Test
    func anUninstalledAuthorityIsNotTrusted() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "fixture.pem")
            try Data(Self.fixturePEM.utf8).write(to: url)

            #expect(SecurityCertificateTrustEvaluator().isTrusted(certificateAt: url) == false)
        }
    }

    @Test
    func rejectsUnparseableContent() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "broken.pem")
            try Data("not a certificate".utf8).write(to: url)

            #expect(throws: CertificateInspectionError.unsupportedFormat) {
                try SecurityCertificateInspector().details(forCertificateAt: url)
            }
        }
    }

    private static let fixturePEM = """
    -----BEGIN CERTIFICATE-----
    MIIDJTCCAg2gAwIBAgIUH1qZ1vDgQXhVjpxJrHukbtf1ZhEwDQYJKoZIhvcNAQEL
    BQAwHDEaMBgGA1UEAwwRZml4dHVyZS5sb2NhbGhvc3QwHhcNMjYxMDE5MTczMjE2
    WhcNMzYxMDE2MTczMjE2WjAcMRowGAYDVQQDDBFmaXh0dXJlLmxvY2FsaG9zdDCC
    ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJE0938iDcOM0b4lw44efULH
    pesYCXHZ7QpizUSp4GfAgRIOLtm8ccgEtLyYrHkf8ACum31gzvNzvKKqw4h4Xabg
    m2TVR9pWPEKFszmdt69ARWMsDd5r0/UtkxI39EsbhEMWfJ4KHEVQh/7yq9DNPqe3
    Au0jjBiyyPycgBNMCzCHZAMOzd5G37/wYeQ0pOokOaNhtD3sSdmqOka2px/PLVAb
    Eowa8XSVI/Bt2ABRsoWLLVS6ZUDipBeLfbnyDMZLddEdHgWZeQb4C1pqMhjWxATk
    fKhwjpTONTK4If9WQBVyhOsiEMr9Qp7RoQ/K6kb0frw0UC6LPRuTtlcwF7BIf70C
    AwEAAaNfMF0wHQYDVR0OBBYEFEyI6MfZXUyAeuWwv6asXrLunXV5MA8GA1UdEwEB
    /wQFMAMBAf8wKwYDVR0RBCQwIoIRZml4dHVyZS5sb2NhbGhvc3SCDWFwaS5sb2Nh
    bGhvc3QwDQYJKoZIhvcNAQELBQADggEBAGoSTsKv1DHQIxBaXwjDjEq9UWjG5/n4
    YhLitCyTbIDy8cDxmYa8qLMOUYjO/E7BHSJ+Z12go69CWq7O2/L5eIvxq5wOkiwx
    JE3IOz1HZ1VP6S+65Q52cpQJ1hDUpu2JHTx9Ic5fMU/fZhodNTJmVaKCYstzM/9w
    IUKlc6B3XrRf+f8x/ejB45GHnNf6HCqQbaSXJHeEDiKcqz0G/m8F2e4dL3ZS0zM7
    ULHXDM0R9DQsd6EM5mxVhnWWEfVc4HhpaLqa9iQWb6NfBnjGRE94XOrhPOMKF8qT
    5XYuDP/D3FFZ0ud81dP+Ef8nX+hXIEdaCGUyryp6VJmGzX+d6g049vI=
    -----END CERTIFICATE-----
    """

    private static let expectedExpiry: Date = {
        var components = DateComponents()
        components.year = 2036
        components.month = 10
        components.day = 16
        components.hour = 17
        components.minute = 32
        components.second = 16
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()
}
