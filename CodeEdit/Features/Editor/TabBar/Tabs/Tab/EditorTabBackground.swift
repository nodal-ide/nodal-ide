//
//  EditorTabBackground.swift
//  CodeEdit
//
//  Created by Austin Condiff on 1/17/23.
//

import SwiftUI

struct EditorTabBackground: View {
    var isActive: Bool
    var isPressing: Bool
    var isDragging: Bool

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.theme)
    private var palette

    @Environment(\.controlActiveState)
    private var activeState

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    private var inHoldingState: Bool {
        isPressing || isDragging
    }

    var body: some View {
        ZStack {
            if isActive {
                if palette.isSolid {
                    palette.tabActiveBackground
                } else {
                    if #available(macOS 26, *) {
                        GlassEffectView()
                    } else {
                        EffectView(.contentBackground)
                    }
                    palette.tabActiveBackground
                        .opacity(0.45)
                }

                palette.accent
                    .hueRotation(.degrees(-5))
                    .opacity(
                        colorScheme == .dark
                        ? activeState == .inactive ? 0.22 : inHoldingState ? 0.33 : 0.26
                        : activeState == .inactive ? 0.1 : inHoldingState ? 0.27 : 0.2
                    )
                    .saturation(isActiveEditor ? 1.0 : 0.0)
            } else if palette.isSolid {
                palette.tabInactiveBackground
            }

            if colorScheme == .dark {
                // Highlight (if in dark mode)
                Color(.white)
                    .blendMode(.plusLighter)
                    .opacity(
                        isActive
                        ? activeState == .inactive ? 0.04 : inHoldingState ? 0.14 : 0.09
                        : isPressing ? 0.05 : 0
                    )
            }

            if isDragging && !isActive {
                // Dragging color (if not active)
                Color(.unemphasizedSelectedTextBackgroundColor)
                    .opacity(0.85)
            }

            if !isActive && isPressing {
                Color(.unemphasizedSelectedTextBackgroundColor)
            }
        }
    }
}

struct EditorTabBackground_Previews: PreviewProvider {
    static var previews: some View {
        EditorTabBackground(isActive: false, isPressing: false, isDragging: false)
    }
}
