//
//  PanelDivider.swift
//  
//
//  Created by Austin Condiff on 5/10/22.
//

import SwiftUI

struct PanelDivider: View {
    @Environment(\.theme)
    private var palette

    var body: some View {
        Divider()
            .opacity(0)
            .overlay(palette.separator.opacity(0.8))
    }
}
