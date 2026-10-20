import Foundation
import Testing
@testable import CodeEdit

struct LocalSiteActionPlannerTests {
    private func enabled(domain: String = "app.localhost") -> LocalSiteSettings {
        var settings = LocalSiteSettings()
        settings.enabled = true
        settings.domain = domain
        return settings
    }

    private func action(
        from old: LocalSiteSettings,
        runtimes oldRuntimes: WorkspaceRuntimes = .init(),
        to new: LocalSiteSettings,
        runtimes newRuntimes: WorkspaceRuntimes = .init()
    ) -> LocalSiteAction {
        LocalSiteActionPlanner.action(
            from: old,
            runtimes: oldRuntimes,
            to: new,
            runtimes: newRuntimes
        )
    }

    @Test
    func noChangeIsNoOp() {
        let settings = enabled()
        #expect(action(from: settings, to: settings) == .none)
    }

    @Test
    func enablingStartsAndDisablingStops() {
        #expect(action(from: .init(), to: enabled()) == .start)

        var stopping = enabled()
        stopping.enabled = false
        #expect(action(from: enabled(), to: stopping) == .stop)
    }

    @Test
    func disabledChangesAreIgnored() {
        var old = LocalSiteSettings()
        old.domain = "one.localhost"
        var new = LocalSiteSettings()
        new.domain = "two.localhost"
        #expect(action(from: old, to: new) == .none)
    }

    @Test
    func nginxOnlyChangesReload() {
        var old = enabled()
        var new = enabled()

        new.domain = "renamed.localhost"
        #expect(action(from: old, to: new) == .reloadNginx)

        old = enabled()
        new = enabled()
        new.documentRoot = "public"
        #expect(action(from: old, to: new) == .reloadNginx)

        old = enabled()
        new = enabled()
        new.routing = .frontController
        #expect(action(from: old, to: new) == .reloadNginx)

        old = enabled()
        new = enabled()
        new.entryFile = "app.php"
        #expect(action(from: old, to: new) == .reloadNginx)

        old = enabled()
        new = enabled()
        new.https = false
        #expect(action(from: old, to: new) == .reloadNginx)
    }

    @Test
    func phpVersionChangeRestartsFPM() {
        var old = enabled()
        var new = enabled()
        new.phpVersion = "8.4"
        #expect(action(from: old, to: new) == .restartFPM)

        old = enabled()
        new = enabled()
        old.phpVersion = "8.3"
        new.phpVersion = "8.4"
        #expect(action(from: old, to: new) == .restartFPM)
    }

    @Test
    func phpRuntimePinChangeRestartsFPM() {
        var runtimes = WorkspaceRuntimes()
        runtimes.php.version = "8.4"
        #expect(action(from: enabled(), runtimes: .init(), to: enabled(), runtimes: runtimes) == .restartFPM)
    }

    @Test
    func unrelatedRuntimePinChangeIsIgnored() {
        var runtimes = WorkspaceRuntimes()
        runtimes.node.version = "22"
        #expect(action(from: enabled(), runtimes: .init(), to: enabled(), runtimes: runtimes) == .none)
    }

    @Test
    func proxyChangesRestartUpstream() {
        var old = enabled()
        old.handler = .proxy
        var new = old
        new.proxy.port = 9999
        #expect(action(from: old, to: new) == .restartUpstream)

        old = enabled()
        old.handler = .proxy
        new = old
        new.proxy.startCommand = "npm run dev"
        #expect(action(from: old, to: new) == .restartUpstream)
    }

    @Test
    func proxySettingsIgnoredForPHPHandler() {
        let old = enabled()
        var new = enabled()
        new.proxy.port = 9999
        #expect(action(from: old, to: new) == .none)
    }

    @Test
    func handlerChangeRestartsEverything() {
        var new = enabled()
        new.handler = .proxy
        #expect(action(from: enabled(), to: new) == .restartAll)
    }

    @Test
    func openInBrowserChangeIsIgnored() {
        var new = enabled()
        new.openInBrowser = false
        #expect(action(from: enabled(), to: new) == .none)
    }
}
