import Foundation

struct PHPInstallOptions {
    var installXdebug: Bool

    static let `default` = PHPInstallOptions(installXdebug: true)
}
