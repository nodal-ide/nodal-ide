//
//  DocumentCloseConfirmation.swift
//  CodeEdit
//
//  One place to ask the user whether a document with unsaved changes may close.
//

import AppKit
import Foundation

/// The receiver for the standard `NSDocument` save/discard/cancel close confirmation.
///
/// Wraps the `canClose(withDelegate:shouldClose:contextInfo:)` callback so callers get a plain `Bool`
/// instead of managing an `UnsafeMutablePointer<Bool>` and a selector.
final class CloseConfirmationTarget: NSObject {
    static let shared = CloseConfirmationTarget()

    var shouldClose = true

    @objc
    func document(
        _ document: NSDocument,
        shouldClose: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        self.shouldClose = shouldClose
    }
}

enum DocumentCloseConfirmation {
    /// Presents the save/discard/cancel panel when `document` has unsaved changes and returns whether it
    /// may close. Returns `true` when the document has no unsaved changes.
    static func confirmClose(of document: NSDocument) -> Bool {
        guard document.isDocumentEdited else { return true }
        let target = CloseConfirmationTarget.shared
        target.shouldClose = true
        document.canClose(
            withDelegate: target,
            shouldClose: #selector(CloseConfirmationTarget.document(_:shouldClose:contextInfo:)),
            contextInfo: nil
        )
        return target.shouldClose
    }
}
