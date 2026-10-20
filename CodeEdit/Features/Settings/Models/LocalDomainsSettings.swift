//
//  LocalDomainsSettings.swift
//  CodeEdit
//
//  Global preferences for local development domains (ports, auto-start, log retention, defaults).
//

import Foundation

extension SettingsData {
    struct LocalDomainsSettings: Codable, Hashable, SearchableSettingsPage {
        enum PortMode: String, Codable, CaseIterable, Identifiable, Sendable {
            /// nginx binds unprivileged 8080/8443; URLs include the port.
            case highPorts
            /// A credential-prompted relay binds 80/443 and forwards to nginx on 18080/18443.
            case privilegedRelay

            var id: String { rawValue }

            var title: String {
                switch self {
                case .highPorts: return "High Ports"
                case .privilegedRelay: return "Portless (80/443)"
                }
            }

            var detail: String {
                switch self {
                case .highPorts:
                    return "Serves on 8080 and 8443 without asking for administrator access."
                case .privilegedRelay:
                    return "Serves on 80 and 443; macOS asks for your password once per session."
                }
            }
        }

        static let defaultLogRetentionBytes = 5 * 1024 * 1024
        static let defaultLogRetentionCount = 3
        static let minimumLogRetentionBytes = 64 * 1024
        static let maximumLogRetentionBytes = 1024 * 1024 * 1024
        static let maximumLogRetentionCount = 20

        var searchKeys: [String] {
            [
                "Local Domains",
                "Port Mode",
                "Auto-start Sites",
                "Log Retention",
                "HTTPS by Default",
                "Open Browser on Start"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        var portMode: PortMode = .highPorts

        /// Starts enabled sites when a workspace opens.
        var autoStartSitesOnOpen: Bool = false

        /// Leaves the shared nginx master running after the last site stops.
        var keepNginxRunningWhenIdle: Bool = false

        /// Rotate a log once it reaches this size.
        var logRetentionBytes: Int = defaultLogRetentionBytes

        /// Number of rotated log archives to keep (0 discards the active log on rotation).
        var logRetentionCount: Int = defaultLogRetentionCount

        /// Default for new sites; each site can override it.
        var httpsByDefault: Bool = true

        /// Opens the site URL after a successful start.
        var openBrowserOnStart: Bool = true

        init() {}

        /// Tolerant decoder: missing, mistyped, or out-of-range values fall back to defaults instead of
        /// dropping every global preference.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let portMode = (try? container.decode(String.self, forKey: .portMode))
                .flatMap(PortMode.init(rawValue:))
            self.portMode = portMode ?? .highPorts

            self.autoStartSitesOnOpen = (try? container.decode(Bool.self, forKey: .autoStartSitesOnOpen))
                ?? false
            self.keepNginxRunningWhenIdle = (try? container.decode(
                Bool.self,
                forKey: .keepNginxRunningWhenIdle
            )) ?? false

            let retentionBytes = (try? container.decode(Int.self, forKey: .logRetentionBytes))
                ?? Self.defaultLogRetentionBytes
            self.logRetentionBytes = Self.clampBytes(retentionBytes)

            let retentionCount = (try? container.decode(Int.self, forKey: .logRetentionCount))
                ?? Self.defaultLogRetentionCount
            self.logRetentionCount = min(max(retentionCount, 0), Self.maximumLogRetentionCount)

            self.httpsByDefault = (try? container.decode(Bool.self, forKey: .httpsByDefault)) ?? true
            self.openBrowserOnStart = (try? container.decode(Bool.self, forKey: .openBrowserOnStart)) ?? true
        }

        private static func clampBytes(_ bytes: Int) -> Int {
            min(max(bytes, minimumLogRetentionBytes), maximumLogRetentionBytes)
        }
    }
}
