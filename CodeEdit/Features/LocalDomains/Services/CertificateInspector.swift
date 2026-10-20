import Foundation
import Security

struct CertificateDetails: Equatable, Sendable {
    let notAfter: Date
    let domains: [String]
}

enum CertificateInspectionError: Error, Equatable, LocalizedError {
    case unreadable(path: String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "Could not read the certificate at \(path)."
        case .unsupportedFormat:
            return "The certificate could not be parsed."
        }
    }
}

protocol CertificateInspecting: Sendable {
    func details(forCertificateAt url: URL) throws -> CertificateDetails
}

/// Reads a PEM certificate's expiry and DNS SANs using the Security framework (no child processes).
struct SecurityCertificateInspector: CertificateInspecting {
    func details(forCertificateAt url: URL) throws -> CertificateDetails {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CertificateInspectionError.unreadable(path: url.path(percentEncoded: false))
        }

        let der = try Self.der(fromPEM: data)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw CertificateInspectionError.unsupportedFormat
        }

        let oids = [kSecOIDX509V1ValidityNotAfter, kSecOIDSubjectAltName] as CFArray
        guard let values = SecCertificateCopyValues(certificate, oids, nil) as? [CFString: Any],
              let notAfter = Self.date(from: values[kSecOIDX509V1ValidityNotAfter]) else {
            throw CertificateInspectionError.unsupportedFormat
        }

        return CertificateDetails(
            notAfter: notAfter,
            domains: Self.domains(from: values[kSecOIDSubjectAltName])
        )
    }

    /// Strips the PEM armor and decodes the base64 body into DER.
    static func der(fromPEM data: Data) throws -> Data {
        guard let pem = String(data: data, encoding: .utf8) else {
            throw CertificateInspectionError.unsupportedFormat
        }
        let base64 = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: base64), !der.isEmpty else {
            throw CertificateInspectionError.unsupportedFormat
        }
        return der
    }

    private static func date(from entry: Any?) -> Date? {
        guard let entry = entry as? [CFString: Any],
              let value = entry[kSecPropertyKeyValue] else {
            return nil
        }
        if let date = value as? Date {
            return date
        }
        // Modern macOS reports validity as a number of seconds since the 2001 reference date.
        if let number = value as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: number.doubleValue)
        }
        return nil
    }

    private static func domains(from entry: Any?) -> [String] {
        guard let entry = entry as? [CFString: Any],
              let items = entry[kSecPropertyKeyValue] as? [[CFString: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let label = item[kSecPropertyKeyLabel] as? String,
                  label.localizedCaseInsensitiveContains("dns"),
                  let value = item[kSecPropertyKeyValue] as? String else {
                return nil
            }
            return value.lowercased()
        }
    }
}
