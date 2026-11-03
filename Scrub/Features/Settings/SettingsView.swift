import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            // Each pane is sized to its content, and the window resizes between them like System Settings.
            Tab("General", systemImage: "gearshape") { GeneralSettings().frame(width: 560, height: 610) }
            Tab("Protected", systemImage: "lock.shield") { ProtectedSettings().frame(width: 560, height: 440) }
            Tab("Projects", systemImage: "folder") { ProjectSettings().frame(width: 560, height: 440) }
            Tab("About", systemImage: "info.circle") { AboutSettings().frame(width: 560, height: 380) }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = state.settings
        Form {
            Section("Cleaning") {
                Picker("Caches and logs", selection: $settings.cacheRemovalMode) {
                    ForEach(RemovalMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Project build folders", selection: $settings.purgeRemovalMode) {
                    ForEach(RemovalMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Skip caches of apps that are running", isOn: $settings.skipRunningApps)
                Text("Apps, leftovers, installers and backups always go to the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Selection") {
                Stepper("Keep projects active in the last \(settings.purgeRecentDays) days", value: $settings.purgeRecentDays, in: 0...90)
                Stepper("Keep installers newer than \(settings.installerAgeDays) days", value: $settings.installerAgeDays, in: 0...180)
            }
            Section("App") {
                Toggle("Show in menu bar", isOn: $settings.showMenuBarExtra)
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { Updater.shared.automaticallyChecks },
                    set: { Updater.shared.automaticallyChecks = $0 }))
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                LabeledContent("Full Disk Access") {
                    if state.hasFullDiskAccess {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") { SystemAccess.openFullDiskAccessSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProtectedSettings: View {
    @Environment(AppState.self) private var state
    @State private var selection: String?

    var body: some View {
        @Bindable var settings = state.settings
        VStack(alignment: .leading, spacing: 10) {
            Text("Scrub never removes these files or anything inside these folders.")
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(settings.protectedPaths, id: \.self) { path in
                    Label(path, systemImage: "lock.fill").tag(path)
                }
            }
            .listStyle(.bordered)
            .overlay {
                if settings.protectedPaths.isEmpty {
                    Text("No protected items. Right-click any file in Scrub to protect it.").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Add…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    guard panel.runModal() == .OK else { return }
                    for url in panel.urls where !settings.protectedPaths.contains(Paths.abbreviate(url.path)) {
                        settings.protectedPaths.append(Paths.abbreviate(url.path))
                    }
                }
                Button("Remove") { settings.protectedPaths.removeAll { $0 == selection } }
                    .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(20)
    }
}

private struct ProjectSettings: View {
    @Environment(AppState.self) private var state
    @State private var selection: String?

    var body: some View {
        @Bindable var settings = state.settings
        VStack(alignment: .leading, spacing: 10) {
            Text("Project Purge looks for build folders up to six levels inside these locations.")
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(settings.projectRoots, id: \.self) { path in
                    HStack {
                        Label(path, systemImage: "folder.fill")
                        Spacer()
                        if !Paths.isDirectory(Paths.expand(path)) { Text("Not found").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .tag(path)
                }
            }
            .listStyle(.bordered)
            HStack {
                Button("Add…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true
                    guard panel.runModal() == .OK else { return }
                    for url in panel.urls where !settings.projectRoots.contains(Paths.abbreviate(url.path)) {
                        settings.projectRoots.append(Paths.abbreviate(url.path))
                    }
                }
                Button("Remove") { settings.projectRoots.removeAll { $0 == selection } }.disabled(selection == nil)
                Spacer()
                Button("Restore Defaults") { settings.projectRoots = AppSettings.defaultProjectRoots }
            }
        }
        .padding(20)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
            Text("Scrub").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("Check for Updates…") { Task { await Updater.shared.check(userInitiated: true) } }
            Text("A free, open-source Mac cleaner and optimizer.\nMIT License.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Link("GitHub", destination: URL(string: "https://github.com/nearbycoder/scrub")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Website", destination: URL(string: "https://nearbycoder.github.io/scrub/")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Report an Issue", destination: URL(string: "https://github.com/nearbycoder/scrub/issues")!)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
