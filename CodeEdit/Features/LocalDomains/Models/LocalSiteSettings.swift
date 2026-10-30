import Foundation

enum LocalSiteHandler: String, CaseIterable, Codable, Identifiable {
    case phpFPM = "php-fpm"
    case proxy
    case staticFiles = "static"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phpFPM: return "PHP-FPM"
        case .proxy: return "Reverse Proxy"
        case .staticFiles: return "Static Files"
        }
    }

    var systemImage: String {
        switch self {
        case .phpFPM: return "p.circle.fill"
        case .proxy: return "arrow.triangle.branch"
        case .staticFiles: return "doc.text"
        }
    }
}

enum LocalSiteRouting: String, CaseIterable, Codable, Identifiable {
    case directory
    case frontController = "front-controller"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .directory: return "Directory"
        case .frontController: return "Front Controller"
        }
    }
}

struct LocalSiteProxySettings: Codable, Hashable {
    var port: Int = 9000
    var startCommand: String = ""
    var workingDirectory: String = ""

    init() { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 9000
        self.startCommand = try container.decodeIfPresent(String.self, forKey: .startCommand) ?? ""
        self.workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
    }

    func isEmpty() -> Bool {
        port == 9000 && startCommand.isEmpty && workingDirectory.isEmpty
    }
}

struct LocalSiteSettings: Codable, Hashable {
    var enabled: Bool = false
    var domain: String = ""
    var handler: LocalSiteHandler = .phpFPM
    var https: Bool = true
    var documentRoot: String = ""
    var routing: LocalSiteRouting = .frontController
    var entryFile: String = "index.php"
    var phpVersion: String?
    var openInBrowser: Bool = true
    var proxy: LocalSiteProxySettings = .init()

    init() { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? ""
        self.https = try container.decodeIfPresent(Bool.self, forKey: .https) ?? true
        self.documentRoot = try container.decodeIfPresent(String.self, forKey: .documentRoot) ?? ""
        self.entryFile = try container.decodeIfPresent(String.self, forKey: .entryFile) ?? "index.php"

        let handler = try container.decodeIfPresent(String.self, forKey: .handler)
        self.handler = handler.flatMap(LocalSiteHandler.init(rawValue:)) ?? .phpFPM

        let routing = try container.decodeIfPresent(String.self, forKey: .routing)
        self.routing = routing.flatMap(LocalSiteRouting.init(rawValue:)) ?? .frontController

        self.openInBrowser = try container.decodeIfPresent(Bool.self, forKey: .openInBrowser) ?? true
        self.proxy = try container.decodeIfPresent(LocalSiteProxySettings.self, forKey: .proxy) ?? .init()

        let version = try container.decodeIfPresent(String.self, forKey: .phpVersion)
        self.phpVersion = (version?.isEmpty ?? true) ? nil : version
    }

    func isEmpty() -> Bool {
        !enabled
            && domain.isEmpty
            && handler == .phpFPM
            && https
            && documentRoot.isEmpty
            && routing == .frontController
            && entryFile == "index.php"
            && (phpVersion?.isEmpty ?? true)
            && openInBrowser
            && proxy.isEmpty()
    }
}
