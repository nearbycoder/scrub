import SwiftUI

@main
struct ScrubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared
    @State private var settings = AppSettings.shared

    var body: some Scene {
        Window("Scrub", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await Updater.shared.check(userInitiated: true) } }
            }
            CommandMenu("Scan") {
                Button("Smart Scan") { state.section = .clean; state.clean.scan() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Analyze Home Folder") {
                    state.section = .analyze
                    if let home = state.analyze.scopes.first { state.analyze.scan(home) }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Find Build Folders") { state.section = .purge; state.purge.scan() }
            }
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { state.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }

        MenuBarExtra(isInserted: $settings.showMenuBarExtra) {
            MenuBarView()
                .environment(state)
        } label: {
            Image(nsImage: BrandMark.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `-appearance light` or `-appearance dark` overrides the system setting, for screenshots.
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        SystemMonitor.shared.start()
        DemoDirector.startIfRequested()
        Updater.shared.checkInBackgroundIfDue()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.showMenuBarExtra
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshAccess()
    }
}
