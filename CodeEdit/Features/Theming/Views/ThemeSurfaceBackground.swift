import SwiftUI

struct ThemeSurfaceBackground: View {
    @Environment(\.theme)
    private var palette

    let surface: ThemeSurface

    var body: some View {
        ZStack {
            if palette.isSolid {
                palette.color(for: surface)
            } else {
                EffectView(surface.material, blendingMode: .withinWindow)
                palette.color(for: surface).opacity(surface.systemTintOpacity)
            }
        }
    }
}

extension View {
    func themeSurface(_ surface: ThemeSurface) -> some View {
        background { ThemeSurfaceBackground(surface: surface) }
    }
}
