//
//  SplitViewControllerView.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 20/02/2023.
//

import SwiftUI

struct SplitViewControllerView: NSViewControllerRepresentable {

    var axis: Axis
    var dividerStyle: CodeEditDividerStyle
    var children: _VariadicView.Children
    @Binding var viewController: () -> SplitViewController?

    func makeNSViewController(context: Context) -> SplitViewController {
        let controller = SplitViewController(axis: axis, parentView: self) { controller in
            updateItems(controller: controller)
        }
        return controller
    }

    func updateNSViewController(_ controller: SplitViewController, context: Context) {
        updateItems(controller: controller)
        controller.setDividerStyle(dividerStyle)
    }

    private func updateItems(controller: SplitViewController) {
        var hasChanged = false
        // Reorder viewcontrollers if needed and add new ones.
        controller.items = children.map { child in
            let item: SplitViewItem
            if let foundItem = controller.items.first(where: { $0.id == child.id }) {
                item = foundItem
                item.update(child: child)
            } else {
                hasChanged = true
                item = SplitViewItem(child: child)
            }
            return item
        }

        controller.splitViewItems = controller.items.map(\.item)

        if hasChanged && controller.splitViewItems.count > 1 {
            let splitView = controller.splitView
            let numerator = splitView.isVertical ? splitView.frame.width : splitView.frame.height

            for idx in 0..<controller.items.count-1 {
                // If the next view is collapsed, don't reposition the divider.
                guard !controller.items[idx+1].item.isCollapsed else { continue }

                // This method needs to be run twice to ensure the split works correctly if split vertical.
                // I've absolutely no idea why but it works.
                splitView.setPosition(
                    CGFloat(idx + 1) * numerator/CGFloat(controller.items.count),
                    ofDividerAt: idx
                )
                splitView.setPosition(
                    CGFloat(idx + 1) * numerator/CGFloat(controller.items.count),
                    ofDividerAt: idx
                )
            }
        }
    }
}

final class SplitViewController: NSSplitViewController {
    final class CustomSplitView: NSSplitView {
        @Invalidating(.display)
        var customDividerStyle: CodeEditDividerStyle = .system(.thin) {
            didSet {
                switch customDividerStyle {
                case .system(let dividerStyle):
                    self.dividerStyle = dividerStyle
                case .editorDivider:
                    return
                }
            }
        }

        init() {
            super.init(frame: .zero)
            dividerStyle = .thin
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var dividerColor: NSColor {
            customDividerStyle.customColor ?? super.dividerColor
        }

        override var dividerThickness: CGFloat {
            customDividerStyle.customThickness ?? super.dividerThickness
        }

        /// Shows the proper resize cursor over each divider (AppKit's default is inconsistent across
        /// split views), covering the widened grab area.
        override func resetCursorRects() {
            super.resetCursorRects()
            guard subviews.count > 1 else { return }
            let cursor: NSCursor = isVertical ? .resizeLeftRight : .resizeUpDown
            let grab: CGFloat = 5
            for index in 0..<(subviews.count - 1) {
                let leading = subviews[index].frame
                guard !leading.isEmpty else { continue }
                let rect: NSRect = isVertical
                    ? NSRect(x: leading.maxX, y: 0, width: dividerThickness, height: bounds.height)
                    : NSRect(x: 0, y: leading.maxY, width: bounds.width, height: dividerThickness)
                addCursorRect(rect.insetBy(dx: isVertical ? -grab : 0, dy: isVertical ? 0 : -grab), cursor: cursor)
            }
        }

        override func drawDivider(in rect: NSRect) {
            let safeRect = NSRect(
                x: rect.origin.x,
                y: max(rect.origin.y, safeAreaRect.origin.y),
                width: isVertical ? dividerThickness : rect.width,
                height: isVertical ? safeAreaRect.height : dividerThickness
            )
            super.drawDivider(in: safeRect)
        }
    }

    var items: [SplitViewItem] = []
    var axis: Axis
    var parentView: SplitViewControllerView?

    var setUpItems: ((SplitViewController) -> Void)?

    init(axis: Axis, parentView: SplitViewControllerView?, setUpItems: ((SplitViewController) -> Void)?) {
        self.axis = axis
        self.parentView = parentView
        self.setUpItems = setUpItems
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        splitView = CustomSplitView()
        super.loadView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = axis != .vertical
        setUpItems?(self)
        DispatchQueue.main.async { [weak self] in
            self?.parentView?.viewController = { [weak self] in
                self
            }
        }
    }

    override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // For some reason, AppKit _really_ wants to hide dividers when there's only one item (and no dividers)
        // so we do this check for them.
        guard items.count > 1 else { return false }
        return super.splitView(splitView, shouldHideDividerAt: dividerIndex)
    }

    /// Enlarges the draggable region around a divider.
    ///
    /// Dividers can be as thin as a single pixel, which makes them very hard to grab. This widens the
    /// effective (grab) rect without changing how the divider is drawn.
    override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let extra: CGFloat = 4
        if splitView.isVertical {
            return proposedEffectiveRect.insetBy(dx: -extra, dy: 0)
        }
        return proposedEffectiveRect.insetBy(dx: 0, dy: -extra)
    }

    func setDividerStyle(_ dividerStyle: CodeEditDividerStyle) {
        guard let splitView = splitView as? CustomSplitView else {
            return
        }
        splitView.customDividerStyle = dividerStyle
    }

    func collapse(for id: AnyHashable, enabled: Bool) {
        guard let item = items.first(where: { $0.id == id })?.item else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = CodeEditAnimations.panelCollapseDuration
            item.animator().isCollapsed = enabled
        }
    }
}
