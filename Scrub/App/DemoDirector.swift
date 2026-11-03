import SwiftUI
import Observation

/// Plays a scripted tour of the app for screen recordings: `Scrub -demo YES`.
/// It never cleans real files; Project Purge only runs against folders passed in `-projectRoots`.
@Observable
final class DemoDirector {
    static let shared = DemoDirector()
    static var isActive: Bool { UserDefaults.standard.bool(forKey: "demo") }

    var caption: String?

    static func startIfRequested() {
        guard isActive else { return }
        Task { @MainActor in await shared.run() }
    }

    private func say(_ text: String?) {
        withAnimation(.smooth(duration: 0.4)) { caption = text }
    }

    private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func wait(until condition: () -> Bool, timeout: Double = 90) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(150)) }
    }

    private func go(_ section: AppSection) {
        AppState.shared.section = section
    }

    @MainActor
    private func run() async {
        let s = AppState.shared
        await wait(1)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }), let screen = window.screen ?? NSScreen.main {
            let size = NSSize(width: 1280, height: 800)
            let frame = screen.visibleFrame
            window.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true, animate: false)
            // Recordings shouldn't capture notifications or stray system prompts.
            window.level = .statusBar
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        await wait(3)

        go(.overview)
        say("Scrub — a free, native Mac cleaner for macOS Tahoe")
        await wait(4.5)

        say("Smart Clean finds caches, logs and leftovers in seconds")
        go(.clean)
        s.clean.scan()
        await wait(until: { s.clean.phase == .ready })
        await wait(1.5)
        say("Review every category and every file before anything is removed")
        for id in ["chrome", "xcode-derived", "user-caches", "homebrew"] where s.clean.resultByID[id] != nil {
            s.clean.selectedRuleID = id
            await wait(1.6)
        }
        await wait(1)
        if let rule = s.clean.results.first(where: { $0.isSelected && $0.rule.group == .developer }) {
            s.clean.setSelected(rule, false)
            await wait(1.2)
            s.clean.setSelected(rule, true)
        }
        await wait(2.5)

        say("Space Lens maps exactly what's using your disk")
        go(.analyze)
        let path = UserDefaults.standard.string(forKey: "analyzePath") ?? Paths.home + "/Library"
        s.analyze.scan(.init(path: path, title: (path as NSString).lastPathComponent, symbol: "folder"))
        await wait(until: { s.analyze.root != nil })
        await wait(3)
        if let big = s.analyze.current?.displayChildren.first(where: { $0.isDirectory && !$0.isUnreadable }) {
            s.analyze.open(big)
            await wait(2.5)
            if let next = s.analyze.current?.displayChildren.first(where: { $0.isDirectory && !$0.isUnreadable }) {
                s.analyze.open(next)
                await wait(2.5)
            }
            s.analyze.goBack()
            await wait(0.8)
            s.analyze.goBack()
        }
        await wait(1.5)

        say("Uninstall apps together with everything they leave behind")
        go(.uninstall)
        if s.uninstall.apps.isEmpty { s.uninstall.load() }
        await wait(until: { s.uninstall.apps.contains { $0.size != nil } })
        await wait(1.5)
        // Show an app that actually left files behind.
        let candidates = s.uninstall.visibleApps.filter { !$0.isRunning && $0.lastUsed != nil }.prefix(15)
        let best = await Task.detached { candidates.max { LeftoverFinder.find(for: $0).count < LeftoverFinder.find(for: $1).count } }.value
        if let app = best ?? s.uninstall.visibleApps.first {
            s.uninstall.selection = [app.path]
            s.uninstall.loadLeftovers(for: app)
        }
        await wait(4)

        say("Project Purge clears build folders from old projects")
        go(.purge)
        s.purge.scan()
        await wait(until: { !s.purge.isScanning && !s.purge.projects.isEmpty }, timeout: 30)
        await wait(5)
        if !s.purge.projects.isEmpty {
            s.purge.purge()
            await wait(until: { !s.purge.isPurging })
        }
        await wait(2)

        say("Maintenance runs the upkeep macOS needs, with Touch ID for sudo")
        go(.optimize)
        await wait(1.5)
        s.optimize.run(only: ["quicklook"])
        await wait(3.5)

        say("Activity shows live CPU, memory, disk, network and battery")
        go(.status)
        await wait(5)

        say("Every cleanup is recorded in History")
        go(.history)
        await wait(3)

        go(.overview)
        say("Free and open source — github.com/nearbycoder/scrub")
        await wait(4)
        say(nil)
        await wait(0.8)
        NSApp.terminate(nil)
    }
}

/// Caption shown during the demo tour. It floats over content, so it uses glass.
struct DemoCaption: View {
    var body: some View {
        if let caption = DemoDirector.shared.caption {
            Text(caption)
                .font(.title3.weight(.medium))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 92)
                .id(caption)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                .allowsHitTesting(false)
        }
    }
}
