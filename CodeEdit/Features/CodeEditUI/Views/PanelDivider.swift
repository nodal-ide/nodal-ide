//
//  PanelDivider.swift
//  
//
//  Created by Austin Condiff on 5/10/22.
//

import SwiftUI

/// The single divider tint used across panels, tab bars and split views so separators match.
enum CodeEditDividerColor {
    static func forScheme(_ scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? .white : .black).opacity(0.12)
    }
}

struct PanelDivider: View {
    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        Divider()
            .opacity(0)
            .overlay(CodeEditDividerColor.forScheme(colorScheme))
    }
}
