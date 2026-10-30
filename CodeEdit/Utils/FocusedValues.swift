import SwiftUI

extension FocusedValues {
    var navigationSplitViewVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[NavSplitViewVisibilityFocusedValueKey.self] }
        set { self[NavSplitViewVisibilityFocusedValueKey.self] = newValue }
    }

    var inspectorVisibility: Binding<Bool>? {
        get { self[InspectorVisibilityFocusedValueKey.self] }
        set { self[InspectorVisibilityFocusedValueKey.self] = newValue }
    }

    var activeWorkspace: WorkspaceDocument? {
        get { self[ActiveWorkspaceFocusedValueKey.self] }
        set { self[ActiveWorkspaceFocusedValueKey.self] = newValue }
    }

    private struct NavSplitViewVisibilityFocusedValueKey: FocusedValueKey {
        typealias Value = Binding<NavigationSplitViewVisibility>
    }

    private struct InspectorVisibilityFocusedValueKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }

    private struct ActiveWorkspaceFocusedValueKey: FocusedValueKey {
        typealias Value = WorkspaceDocument
    }
}
