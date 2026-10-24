//
//  CodeEditSplitViewController.swift
//  CodeEdit
//
//  Created by YAPRYNTSEV Aleksey on 31.12.2022.
//

import Cocoa
import SwiftUI

/// The **window-level** split view controller. It lays out the three top-level panes of a window —
/// the navigator (sidebar), the main content, and the inspector — and owns their collapse/resize
/// behavior (`NSSplitViewItem` spring-loading, haptics, snap widths, state persistence).
///
/// This is deliberately separate from the in-content SwiftUI ``SplitView`` (backed by
/// ``SplitViewControllerView``/``SplitViewController``), which splits *within* a pane (editor
/// groups, utility area). Rule of thumb: window chrome → AppKit here; splitting content inside a
/// pane → SwiftUI ``SplitView``. Divider appearance and resize-cursor behavior for content splits
/// live in one place, ``CodeEditDividerStyle`` + `SplitViewController.CustomSplitView`, not here.
final class CodeEditSplitViewController: NSSplitViewController {
    static let minSidebarWidth = Metrics.Sidebar.minWidth
    static let minInspectorWidth = Metrics.Sidebar.minInspectorWidth
    static let assistantRevealWidth = Metrics.Sidebar.assistantRevealWidth
    static let maxSnapWidth = Metrics.Sidebar.maxSnapWidth
    static let snapWidth = Metrics.Sidebar.snapWidth
    static let minSnapWidth = Metrics.Sidebar.minSnapWidth

    private weak var workspace: WorkspaceDocument?
    private weak var navigatorViewModel: NavigatorAreaViewModel?
    let inspectorViewModel: InspectorAreaViewModel
    private weak var windowRef: NSWindow?
    private unowned var hapticPerformer: NSHapticFeedbackPerformer

    private weak var navigatorItem: NSSplitViewItem?

    // MARK: - Initialization

    init(
        workspace: WorkspaceDocument,
        navigatorViewModel: NavigatorAreaViewModel,
        inspectorViewModel: InspectorAreaViewModel? = nil,
        windowRef: NSWindow,
        hapticPerformer: NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer
    ) {
        self.workspace = workspace
        self.navigatorViewModel = navigatorViewModel
        self.inspectorViewModel = inspectorViewModel ?? InspectorAreaViewModel()
        self.windowRef = windowRef
        self.hapticPerformer = hapticPerformer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let windowRef else {
            // swiftlint:disable:next line_length
            assertionFailure("No WindowRef found, not initialized properly or the window was dereferenced and the controller was not.")
            return
        }

        guard let workspace,
              let navigatorViewModel,
              let editorManager = workspace.editorManager,
              let statusBarViewModel = workspace.statusBarViewModel,
              let utilityAreaModel = workspace.utilityAreaModel,
              let taskManager = workspace.taskManager else {
            // swiftlint:disable:next line_length
            assertionFailure("Missing a workspace model: workspace=\(workspace == nil), navigator=\(navigatorViewModel == nil), editorManager=\(workspace?.editorManager == nil), statusBarModel=\(workspace?.statusBarViewModel == nil), utilityAreaModel=\(workspace?.utilityAreaModel == nil), taskManager=\(workspace?.taskManager == nil)")
            return
        }

        splitView.translatesAutoresizingMaskIntoConstraints = false

        let navigator = makeNavigator(view: SettingsInjector {
            NavigatorAreaView(workspace: workspace, viewModel: navigatorViewModel)
                .environmentObject(workspace)
                .environmentObject(editorManager)
        })

        self.navigatorItem = navigator
        addSplitViewItem(navigator)

        let workspaceView = SettingsInjector {
            WindowObserver(window: WindowBox(value: windowRef)) {
                WorkspaceView()
                    .environmentObject(workspace)
                    .environmentObject(editorManager)
                    .environmentObject(statusBarViewModel)
                    .environmentObject(utilityAreaModel)
                    .environmentObject(taskManager)
                    .environmentObject(workspace.undoRegistration)
            }
        }

        let mainContent = NSSplitViewItem(viewController: NSHostingController(rootView: workspaceView))
        mainContent.titlebarSeparatorStyle = .line
        mainContent.minimumThickness = 200

        addSplitViewItem(mainContent)

        let inspector = makeInspector(view: SettingsInjector {
            InspectorAreaView(viewModel: inspectorViewModel)
                .environmentObject(workspace)
                .environmentObject(editorManager)
        })

        addSplitViewItem(inspector)
    }

    private func makeNavigator(view: some View) -> NSSplitViewItem {
        let navigator = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: view))
        if #unavailable(macOS 26) {
            navigator.titlebarSeparatorStyle = .none
        }
        navigator.isSpringLoaded = true
        navigator.minimumThickness = Self.minSidebarWidth
        navigator.collapseBehavior = .useConstraints
        return navigator
    }

    private func makeInspector(view: some View) -> NSSplitViewItem {
        let inspector = NSSplitViewItem(inspectorWithViewController: NSHostingController(rootView: view))
        inspector.titlebarSeparatorStyle = .none
        inspector.minimumThickness = Self.minInspectorWidth
        inspector.maximumThickness = .greatestFiniteMagnitude
        inspector.collapseBehavior = .useConstraints
        inspector.isSpringLoaded = true
        return inspector
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        guard let workspace else { return }
        workspace.notificationPanel.updateToolbarItem()

        let navigatorWidth = workspace.getFromWorkspaceState(.splitViewWidth) as? CGFloat
        splitView.setPosition(navigatorWidth ?? Self.minSidebarWidth, ofDividerAt: 0)

        if let firstSplitView = splitViewItems.first {
            firstSplitView.isCollapsed = workspace.getFromWorkspaceState(
                .navigatorCollapsed
            ) as? Bool ?? false
        }

        if let lastSplitView = splitViewItems.last {
            lastSplitView.isCollapsed = workspace.getFromWorkspaceState(
                .inspectorCollapsed
            ) as? Bool ?? true
        }

        if let inspectorWidth = workspace.getFromWorkspaceState(.inspectorWidth) as? CGFloat,
           splitView.bounds.width > 0 {
            let width = max(inspectorWidth, Self.minInspectorWidth)
            splitView.setPosition(
                max(Self.minInspectorWidth, splitView.bounds.width - width),
                ofDividerAt: 1
            )
        }

        workspace.notificationPanel.updateToolbarItem()
    }

    // MARK: - NSSplitViewDelegate

    /// Perform the spring loaded navigator splits.
    /// - Note: This could be removed. The only additional functionality this provides over using just the
    ///         `NSSplitViewItem.isSpringLoaded` & `NSSplitViewItem.minimumThickness` is the haptic feedback we add.
    /// - Parameters:
    ///   - splitView: The split view to use.
    ///   - proposedPosition: The proposed drag position.
    ///   - dividerIndex: The index of the divider being dragged.
    /// - Returns: The position to move the divider to.
    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0:
            // Navigator
            if (Self.minSnapWidth...Self.maxSnapWidth).contains(proposedPosition) {
                return Self.snapWidth
            } else if proposedPosition <= Self.minSidebarWidth / 2 {
                hapticCollapse(splitViewItems.first, collapseAction: true)
                return 0
            } else {
                hapticCollapse(splitViewItems.first, collapseAction: false)
                return max(Self.minSidebarWidth, proposedPosition)
            }
        case 1:
            let proposedWidth = splitView.bounds.width - proposedPosition
            if proposedWidth <= Self.minInspectorWidth / 2 {
                hapticCollapse(splitViewItems.last, collapseAction: true)
                return proposedPosition
            } else {
                hapticCollapse(splitViewItems.last, collapseAction: false)
                return min(splitView.bounds.width - Self.minInspectorWidth, proposedPosition)
            }
        default:
            return proposedPosition
        }
    }

    /// Performs a haptic feedback while collapsing or revealing a split item.
    /// If the item was not previously in the new intended state, a haptic `.alignment` feedback is sent.
    /// - Parameters:
    ///   - item: The item to collapse or reveal
    ///   - collapseAction: Whether or not to collapse the item. Set to true to collapse it.
    private func hapticCollapse(_ item: NSSplitViewItem?, collapseAction: Bool) {
        if item?.isCollapsed == !collapseAction {
            hapticPerformer.perform(.alignment, performanceTime: .now)
        }
        item?.isCollapsed = collapseAction
    }

    /// Save the width of the inspector and navigator between sessions.
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard let resizedDivider = notification.userInfo?["NSSplitViewDividerIndex"] as? Int else {
            return
        }

        if resizedDivider == 0 {
            let width: CGFloat
            if #available(macOS 26, *) {
                let panel = splitViewItems[0]
                width = panel.viewController.view.frame.size.width
            } else {
                let panel = splitView.subviews[0]
                width = panel.frame.size.width
            }
            if width > 0 {
                workspace?.addToWorkspaceState(key: .splitViewWidth, value: width)
            }
        } else if resizedDivider == 1 {
            let width = inspectorWidth
            if width > 0 {
                workspace?.addToWorkspaceState(key: .inspectorWidth, value: width)
            }
        }
    }

    var inspectorWidth: CGFloat {
        guard splitViewItems.count > 2 else { return 0 }
        if #available(macOS 26, *) {
            return splitViewItems[2].viewController.view.frame.size.width
        }
        return splitView.subviews.last?.frame.size.width ?? 0
    }

    func ensureInspectorWidth(atLeast minimumWidth: CGFloat) {
        guard splitViewItems.last?.isCollapsed == false, splitView.bounds.width > 0 else { return }
        guard inspectorWidth < minimumWidth else { return }
        let targetPosition = max(Self.minInspectorWidth, splitView.bounds.width - minimumWidth)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            splitView.setPosition(targetPosition, ofDividerAt: 1)
        }
        splitView.adjustSubviews()
    }

    func saveNavigatorCollapsedState(isCollapsed: Bool) {
        workspace?.addToWorkspaceState(key: .navigatorCollapsed, value: isCollapsed)
    }

    func saveInspectorCollapsedState(isCollapsed: Bool) {
        workspace?.addToWorkspaceState(key: .inspectorCollapsed, value: isCollapsed)
    }
}
