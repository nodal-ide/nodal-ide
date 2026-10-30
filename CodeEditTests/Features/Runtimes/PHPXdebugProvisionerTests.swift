@testable import CodeEdit
import Foundation
import Testing

@Suite
struct PHPXdebugProvisionerTests {
    @Test
    func isProvisionedRequiresBothManifestAndIni() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let binDir = tempDir.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runtime = InstalledRuntime(
            kind: .php,
            version: "8.3.0",
            source: .managed,
            executableDirectory: binDir
        )

        let provisioner = PHPXdebugProvisioner.shared
        #expect(!provisioner.isProvisioned(runtime: runtime))

        let confDir = provisioner.confDir(for: runtime)
        try FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)
        try "zend_extension=xdebug\n".write(to: provisioner.iniURL(for: runtime), atomically: true, encoding: .utf8)
        #expect(!provisioner.isProvisioned(runtime: runtime))

        try "{}".write(to: provisioner.manifestURL(for: runtime), atomically: true, encoding: .utf8)
        #expect(provisioner.isProvisioned(runtime: runtime))
        #expect(provisioner.iniScanDir(for: runtime) == confDir.path(percentEncoded: false))
    }

    @Test
    func removeDeletesIniAndManifest() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let binDir = tempDir.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runtime = InstalledRuntime(
            kind: .php,
            version: "8.3.0",
            source: .managed,
            executableDirectory: binDir
        )

        let provisioner = PHPXdebugProvisioner.shared
        let confDir = provisioner.confDir(for: runtime)
        try FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)

        let ini = provisioner.iniURL(for: runtime)
        let manifest = provisioner.manifestURL(for: runtime)

        try "zend_extension=xdebug\n".write(to: ini, atomically: true, encoding: .utf8)
        try """
        {"soPath":"","managedByApp":false,"xdebugVersion":"3.3.0"}
        """.write(to: manifest, atomically: true, encoding: .utf8)

        #expect(provisioner.isProvisioned(runtime: runtime))

        try await provisioner.remove(runtime: runtime)

        #expect(!provisioner.isProvisioned(runtime: runtime))
        #expect(!FileManager.default.fileExists(atPath: ini.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: manifest.path(percentEncoded: false)))
    }
}
