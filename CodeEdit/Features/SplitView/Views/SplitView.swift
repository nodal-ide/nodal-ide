//
//  SplitView.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 22/02/2023.
//

import SwiftUI

/// The **in-content** SwiftUI split view. Splits the content of a single pane along `axis` (editor
/// groups, the utility area, the workspace layout) and is backed by AppKit through
/// ``SplitViewControllerView``/``SplitViewController``.
///
/// This is deliberately separate from ``CodeEditSplitViewController``, which owns the window's
/// top-level navigator/content/inspector panes. Rule of thumb: splitting content inside a pane →
/// this; window chrome → `CodeEditSplitViewController`. All divider styling and resize-cursor
/// behavior (``CodeEditDividerStyle`` + `SplitViewController.CustomSplitView`) lives here, so there
/// is a single divider-resize implementation.
struct SplitView<Content: View>: View {
    var axis: Axis
    var dividerStyle: CodeEditDividerStyle
    var content: Content

    init(axis: Axis, dividerStyle: CodeEditDividerStyle = .system(.thin), @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.dividerStyle = dividerStyle
        self.content = content()
    }

    @State private var viewController: () -> SplitViewController? = { nil }

    var body: some View {
        VStack {
            content.variadic { children in
                SplitViewControllerView(
                    axis: axis,
                    dividerStyle: dividerStyle,
                    children: children,
                    viewController: $viewController
                )
            }
        }
        ._trait(SplitViewControllerLayoutValueKey.self, viewController)
        .accessibilityElement(children: .contain)
    }
}
