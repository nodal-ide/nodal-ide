import AppKit

enum ThemeSurface: String, CaseIterable {
    case window
    case sidebar
    case toolbar
    case tabBar
    case tabActive
    case tabInactive
    case panel
    case overlay
    case control

    var material: NSVisualEffectView.Material {
        switch self {
        case .window, .tabBar, .tabActive, .tabInactive, .panel:
            return .contentBackground
        case .sidebar:
            return .sidebar
        case .toolbar:
            return .headerView
        case .overlay:
            return .popover
        case .control:
            return .menu
        }
    }

    var systemTintOpacity: Double {
        switch self {
        case .window:
            return 0.18
        case .sidebar:
            return 0.2
        case .toolbar:
            return 0.16
        case .tabBar:
            return 0.22
        case .tabActive:
            return 0.24
        case .tabInactive:
            return 0.22
        case .panel:
            return 0.2
        case .overlay:
            return 0.16
        case .control:
            return 0.12
        }
    }
}
