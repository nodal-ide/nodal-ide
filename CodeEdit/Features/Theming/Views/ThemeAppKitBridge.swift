import AppKit
import SwiftUI

struct ThemeAppKitBridge: NSViewRepresentable {
    @Environment(\.theme)
    private var palette

    func makeNSView(context: Context) -> BridgeView {
        BridgeView()
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.palette = palette
    }

    final class BridgeView: NSView {
        var palette: ThemePalette? {
            didSet { applyPalette() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyPalette()
        }

        private func applyPalette() {
            guard let window, let palette else { return }
            window.backgroundColor = NSColor(palette.windowBackground)
        }
    }
}
