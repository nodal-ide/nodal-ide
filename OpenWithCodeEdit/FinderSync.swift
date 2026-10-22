//
//  FinderSync.swift
//  openInCodeEdit
//
//  Created by Wesley de Groot on 03/05/2022.
//

/**
 * For anyone working on this file.
 * print does not output to the console, use NSLog.
 * open "console.app" to debug,
 */

import Cocoa
import FinderSync
import os.log

class CEOpenWith: FIFinderSync {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "FinderSync")

    /// App-group defaults, or standard defaults when the group isn't provisioned. Avoids noisy
    /// `cfprefsd` "detaching from cfprefsd" console output in local (unprovisioned) builds.
    private var sharedDefaults: UserDefaults {
        let suiteName = "app.nodalide.Nodal.shared"
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) != nil else {
            return .standard
        }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    override init() {
        super.init()
        // Add finder sync
        let finderSync = FIFinderSyncController.default()
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            finderSync.directoryURLs = Set<URL>(mountedVolumes)
        }
        // Monitor volumes
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                finderSync.directoryURLs.insert(volumeURL)
            }
        }
    }

    /// Open in CodeEdit (menu) action
    /// - Parameter sender: sender
    @objc
    func openInCodeEditAction(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else {
            return
        }
        let defaults = sharedDefaults

        // Make values compatible to ArrayLiteralElement
        var files = ""

        for obj in items {
            files.append("\(obj.path);")
        }

        guard let codeEdit = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "app.codeedit.CodeEdit"
        ) else { return }

        // Add files to open to openInCEFiles.
        defaults.set(files, forKey: "openInCEFiles")

        NSWorkspace.shared.open(
            [],
            withApplicationAt: codeEdit,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Menu and toolbar item support
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let defaults = sharedDefaults

        // Register enableOpenInCE (enable Open In CodeEdit
        defaults.register(defaults: ["enableOpenInCE": true])

        let menu = NSMenu(title: "")
        let menuItem = NSMenuItem(
            title: "Open in Nodal IDE",
            action: #selector(openInCodeEditAction(_:)),
            keyEquivalent: ""
        )
        menuItem.image = NSImage.init(named: "icon")

        let enableOpenInCE = defaults.bool(forKey: "enableOpenInCE")
        logger.info("Enable Open In CodeEdit value is \(enableOpenInCE, privacy: .public)")
        if enableOpenInCE {
            menu.addItem(menuItem)
        }
        return menu
    }
}
