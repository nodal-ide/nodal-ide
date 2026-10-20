import Foundation

/// The single action a settings change should trigger for a project's local site.
enum LocalSiteAction: Equatable {
    case none
    case start
    case stop
    case reloadNginx
    case restartFPM
    case restartUpstream
    case restartAll
}

/// Pure diff engine that turns a pair of site settings into the minimal action needed.
enum LocalSiteActionPlanner {
    static func action(
        from old: LocalSiteSettings,
        runtimes oldRuntimes: WorkspaceRuntimes,
        to new: LocalSiteSettings,
        runtimes newRuntimes: WorkspaceRuntimes
    ) -> LocalSiteAction {
        guard old.enabled == new.enabled else {
            return new.enabled ? .start : .stop
        }

        guard new.enabled else {
            return .none
        }

        return enabledAction(
            old: old,
            oldRuntimes: oldRuntimes,
            new: new,
            newRuntimes: newRuntimes
        )
    }

    private static func enabledAction(
        old: LocalSiteSettings,
        oldRuntimes: WorkspaceRuntimes,
        new: LocalSiteSettings,
        newRuntimes: WorkspaceRuntimes
    ) -> LocalSiteAction {
        if old.handler != new.handler {
            return .restartAll
        }

        if new.handler == .phpFPM,
           old.phpVersion != new.phpVersion || oldRuntimes.php != newRuntimes.php {
            return .restartFPM
        }

        if new.handler == .proxy, old.proxy != new.proxy {
            return .restartUpstream
        }

        if nginxConfigChanged(old: old, new: new) {
            return .reloadNginx
        }

        return .none
    }

    private static func nginxConfigChanged(old: LocalSiteSettings, new: LocalSiteSettings) -> Bool {
        old.domain != new.domain
            || old.https != new.https
            || old.documentRoot != new.documentRoot
            || old.routing != new.routing
            || old.entryFile != new.entryFile
    }
}
