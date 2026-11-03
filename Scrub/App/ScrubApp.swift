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
                .frame(minWidth: 1020, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Smart Scan") { state.section = .clean; state.clean.scan() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Analyze Home Folder") {
                    state.section = .analyze
                    if let home = state.analyze.scopes.first { state.analyze.scan(home) }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    if index < 9 {
                        Button(section.title) { state.section = section }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
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
            Image(systemName: "bubbles.and.sparkles.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemMonitor.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.showMenuBarExtra
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshAccess()
    }
}
