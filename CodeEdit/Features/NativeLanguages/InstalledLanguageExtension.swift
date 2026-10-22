//
//  InstalledLanguageExtension.swift
//  CodeEdit
//
//  An installed declarative language extension (a pack on disk).
//

import Foundation
import AppKit
import CodeEditLang

/// An installed declarative language extension (a pack on disk).
struct InstalledLanguageExtension: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String?
    let root: URL
    let manifest: LanguageExtensionManifest
    /// Where the pack came from. Only global packs may load native grammars.
    let scope: LanguageExtensionPackScope
    /// Marketplace origin for packages installed from a catalog source.
    let provenance: ExtensionProvenance?

    init(
        id: String,
        name: String,
        version: String?,
        root: URL,
        manifest: LanguageExtensionManifest,
        scope: LanguageExtensionPackScope,
        provenance: ExtensionProvenance? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.root = root
        self.manifest = manifest
        self.scope = scope
        self.provenance = provenance
    }

    /// The framework this pack targets, if any (from `framework` or `activation.framework.requires`).
    var frameworkName: String? { manifest.frameworkName }

    /// A short display line: version and/or author.
    var subtitle: String? {
        [version, manifest.author].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    /// The pack icon (`icon` in the manifest, relative to the pack root) or a default symbol.
    var icon: NSImage {
        if let iconPath = manifest.icon,
           let url = LanguageExtensionPaths.resolve(iconPath, in: root),
           LanguageExtensionPaths.isContained(url, in: root),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let symbol = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: nil) {
            return symbol
        }
        return NSImage()
    }

    static func == (lhs: InstalledLanguageExtension, rhs: InstalledLanguageExtension) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
