import Foundation
import Security

/// Answers whether a certificate is trusted as an anchor by the current system trust settings.
protocol CertificateTrustEvaluating: Sendable {
    func isTrusted(certificateAt url: URL) -> Bool
}

/// Evaluates trust with `SecTrust` so we detect the real keychain state instead of guessing.
struct SecurityCertificateTrustEvaluator: CertificateTrustEvaluating {
    func isTrusted(certificateAt url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let der = try? SecurityCertificateInspector.der(fromPEM: data),
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return false
        }

        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificate, policy, &trust) == errSecSuccess,
              let trust else {
            return false
        }
        return SecTrustEvaluateWithError(trust, nil)
    }
}
