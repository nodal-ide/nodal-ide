//
//  ConflictResolver.swift
//  CodeEdit
//
//  Applies conflict resolutions to file content.
//

import Foundation

enum ConflictResolver {
    /// Replaces a conflict region with the chosen resolution, returning the new content.
    static func applying(_ resolution: ConflictResolution, to conflict: ConflictBlock, in content: String) -> String {
        let nsString = content as NSString
        guard conflict.range.location >= 0, NSMaxRange(conflict.range) <= nsString.length else {
            return content
        }
        return nsString.replacingCharacters(in: conflict.range, with: resolution.text(for: conflict))
    }
}
