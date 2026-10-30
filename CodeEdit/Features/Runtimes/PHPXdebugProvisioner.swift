import Foundation
import OSLog

actor PHPXdebugProvisioner {
    static let shared = PHPXdebugProvisioner()

    private static let logger = Logger(subsystem: "do.upper.nodalide", category: "PHPXdebugProvisioner")

    private struct Manifest: Codable {
        let soPath: String
        let managedByApp: Bool
        let xdebugVersion: String
    }

    private init() {}

    func provision(runtime: InstalledRuntime, progress: @escaping (RuntimeInstallProgress) -> Void) async throws {
        progress(.init(phase: .resolving, message: "Checking Xdebug prerequisites…"))

        let developerPath = RuntimeShell.run("xcode-select -p 2>/dev/null")
        guard !developerPath.isEmpty else {
            throw RuntimeError.installFailed(
                "Xcode Command Line Tools are required. Run `xcode-select --install` in Terminal."
            )
        }

        let phpBin = runtime.executableDirectory.appending(path: "php").path(percentEncoded: false)

        progress(.init(phase: .resolving, message: "Detecting existing Xdebug…"))
        let existingVersion = await runOffMain(
            "'\(phpBin)' -r 'echo extension_loaded(\"xdebug\") ? phpversion(\"xdebug\") : \"\";' 2>/dev/null"
        )
        if !existingVersion.isEmpty {
            progress(.init(phase: .installing, message: "Writing ini for existing Xdebug \(existingVersion)…"))
            try writeIni(for: runtime, soPath: nil)
            let manifest = Manifest(soPath: "", managedByApp: false, xdebugVersion: existingVersion)
            try writeManifest(manifest, for: runtime)
            progress(.init(phase: .done))
            return
        }

        let peclBin = runtime.runtimeRoot.appending(path: "bin/pecl").path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: peclBin) else {
            throw RuntimeError.installFailed(
                "pecl not found at \(peclBin). Ensure the PHP Homebrew keg is fully installed."
            )
        }

        progress(.init(phase: .installing, message: "Building and installing Xdebug…"))
        let soPath = try await buildAndInstall(runtime: runtime, peclBin: peclBin, progress: progress)

        progress(.init(phase: .installing, message: "Writing Xdebug configuration…"))
        try writeIni(for: runtime, soPath: soPath)

        let scanDir = confDir(for: runtime).path(percentEncoded: false)
        let xdebugVersion = await runOffMain(
            "'\(phpBin)' -d php_ini_scan_dir='\(scanDir)' -r 'echo extension_loaded(\"xdebug\") ? phpversion(\"xdebug\") : \"\";' 2>/dev/null"
        )
        let manifest = Manifest(soPath: soPath, managedByApp: true, xdebugVersion: xdebugVersion.isEmpty ? "3.5.3" : xdebugVersion)
        try writeManifest(manifest, for: runtime)
        progress(.init(phase: .done))
    }

    private func buildAndInstall(
        runtime: InstalledRuntime,
        peclBin: String,
        progress: @escaping (RuntimeInstallProgress) -> Void
    ) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "xdebug-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let phpConfigBin = runtime.runtimeRoot.appending(path: "bin/php-config").path(percentEncoded: false)
        let phpizeBin = runtime.runtimeRoot.appending(path: "bin/phpize").path(percentEncoded: false)

        progress(.init(phase: .downloading, message: "Downloading Xdebug source…"))
        let dlResult = await runCommand("cd '\(tempDir.path(percentEncoded: false))' && '\(peclBin)' download xdebug 2>&1")
        guard dlResult.status == 0 else {
            throw RuntimeError.installFailed("Failed to download Xdebug: \(dlResult.output)")
        }

        progress(.init(phase: .extracting, message: "Extracting Xdebug source…"))
        let untarResult = await runCommand("cd '\(tempDir.path(percentEncoded: false))' && tar -xzf xdebug-*.tgz")
        guard untarResult.status == 0 else {
            throw RuntimeError.installFailed("Failed to extract Xdebug archive.")
        }

        guard let srcDirName = try? FileManager.default.contentsOfDirectory(atPath: tempDir.path(percentEncoded: false))
            .first(where: { $0.hasPrefix("xdebug-") && !$0.hasSuffix(".tgz") }) else {
            throw RuntimeError.installFailed("Could not locate extracted Xdebug source directory.")
        }
        let srcPath = tempDir.appending(path: srcDirName).path(percentEncoded: false)

        progress(.init(phase: .installing, message: "Configuring Xdebug build…"))
        let configResult = await runCommand("cd '\(srcPath)' && '\(phpizeBin)' 2>&1 && ./configure --with-php-config='\(phpConfigBin)' 2>&1")
        guard configResult.status == 0 else {
            throw RuntimeError.installFailed("phpize/configure failed:\n\(configResult.output.suffix(400))")
        }

        progress(.init(phase: .installing, message: "Compiling Xdebug…"))
        let makeResult = await runCommand("cd '\(srcPath)' && make -j4 2>&1")
        guard makeResult.status == 0 else {
            throw RuntimeError.installFailed("make failed:\n\(makeResult.output.suffix(400))")
        }

        let builtSo = tempDir.appending(path: "\(srcDirName)/modules/xdebug.so")
        guard FileManager.default.fileExists(atPath: builtSo.path(percentEncoded: false)) else {
            throw RuntimeError.installFailed("Compiled xdebug.so was not found in modules/.")
        }

        let extensionDir = appExtensionsDir(for: runtime)
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        let targetSoURL = extensionDir.appending(path: "xdebug.so")
        if FileManager.default.fileExists(atPath: targetSoURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: targetSoURL)
        }
        try FileManager.default.copyItem(at: builtSo, to: targetSoURL)

        return targetSoURL.path(percentEncoded: false)
    }

    func remove(runtime: InstalledRuntime) async throws {
        let manifestURL = manifestURL(for: runtime)
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            try? FileManager.default.removeItem(at: iniURL(for: runtime))
            return
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        if manifest.managedByApp && !manifest.soPath.isEmpty {
            try? FileManager.default.removeItem(atPath: manifest.soPath)
        }
        try? FileManager.default.removeItem(at: iniURL(for: runtime))
        try FileManager.default.removeItem(at: manifestURL)
        Self.logger.info("Removed Xdebug for PHP \(runtime.version, privacy: .public)")
    }

    nonisolated func isProvisioned(runtime: InstalledRuntime) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestURL(for: runtime).path(percentEncoded: false)),
              fm.fileExists(atPath: iniURL(for: runtime).path(percentEncoded: false)) else {
            return false
        }
        guard let data = try? Data(contentsOf: manifestURL(for: runtime)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return false
        }
        if manifest.managedByApp {
            return !manifest.soPath.isEmpty && fm.fileExists(atPath: manifest.soPath)
        }
        return true
    }

    nonisolated func iniScanDir(for runtime: InstalledRuntime) -> String? {
        guard isProvisioned(runtime: runtime) else { return nil }
        return confDir(for: runtime).path(percentEncoded: false)
    }

    nonisolated func confDir(for runtime: InstalledRuntime) -> URL {
        runtime.runtimeRoot.appending(path: "conf.d", directoryHint: .isDirectory)
    }

    nonisolated func iniURL(for runtime: InstalledRuntime) -> URL {
        confDir(for: runtime).appending(path: "xdebug.ini")
    }

    nonisolated func manifestURL(for runtime: InstalledRuntime) -> URL {
        runtime.runtimeRoot.appending(path: ".xdebug-manifest.json")
    }

    private func appExtensionsDir(for runtime: InstalledRuntime) -> URL {
        let phpConfigBin = runtime.runtimeRoot.appending(path: "bin/php-config").path(percentEncoded: false)
        let extDir = RuntimeShell.run("'\(phpConfigBin)' --extension-dir 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = extDir.isEmpty ? runtime.version : URL(filePath: extDir).lastPathComponent
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".nodalide/runtimes/php/extensions/\(folder)", directoryHint: .isDirectory)
    }

    private func writeIni(for runtime: InstalledRuntime, soPath: String?) throws {
        let dir = confDir(for: runtime)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let port = AppServices.settings.preferences.developerSettings.phpDebugClientPort
        let extensionLine = soPath != nil ? "zend_extension=\(soPath!)" : "zend_extension=xdebug"
        let contents = """
        \(extensionLine)
        xdebug.mode=debug,develop
        xdebug.start_with_request=yes
        xdebug.client_port=\(port)
        xdebug.client_host=127.0.0.1
        xdebug.discover_client_host=0
        xdebug.log_level=0

        """
        try contents.write(to: iniURL(for: runtime), atomically: true, encoding: .utf8)
    }

    private func writeManifest(_ manifest: Manifest, for runtime: InstalledRuntime) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(for: runtime), options: .atomic)
    }

    private func runOffMain(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: RuntimeShell.run(command))
            }
        }
    }

    private func runCommand(_ command: String) async -> (output: String, status: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: RuntimeShell.runResult(command))
            }
        }
    }
}
