import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Sidebar(selection: $state.section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
        }
        .overlay(alignment: .bottom) { DemoCaption() }
        .onAppear { showOnboarding = !state.settings.hasCompletedOnboarding && !DemoDirector.isActive }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { state.settings.hasCompletedOnboarding = true; showOnboarding = false }
                .environment(state)
        }
    }

    @ViewBuilder private var detail: some View {
        switch state.section {
        case .overview: OverviewView()
        case .clean: CleanView()
        case .purge: PurgeView()
        case .installers: InstallersView()
        case .uninstall: UninstallView()
        case .analyze: AnalyzeView()
        case .optimize: OptimizeView()
        case .status: StatusView()
        case .history: HistoryView()
        }
    }
}

struct Sidebar: View {
    @Binding var selection: AppSection
    @Environment(AppState.self) private var state

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(AppSection.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.1) { section in
                        NavigationLink(value: section) {
                            HStack {
                                Label(section.title, systemImage: section.symbol)
                                Spacer(minLength: 4)
                                if let badge = badge(for: section) {
                                    badge.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                } header: {
                    if !group.0.isEmpty { Text(group.0) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { StorageFooter() }
    }

    private func badge(for section: AppSection) -> Text? {
        switch section {
        case .clean where state.clean.phase == .ready && state.clean.totalSelected > 0:
            Text(state.clean.totalSelected.formattedBytes)
        case .purge where state.purge.selectedSize > 0:
            Text(state.purge.selectedSize.formattedBytes)
        default:
            nil
        }
    }
}

/// Startup disk usage pinned to the bottom of the sidebar. Reads only disk values, so it isn't
/// redrawn by the faster CPU and memory samples.
private struct StorageFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let m = state.monitor
        VStack(alignment: .leading, spacing: 8) {
            if !state.hasFullDiskAccess {
                Button {
                    SystemAccess.openFullDiskAccessSettings()
                } label: {
                    Label("Allow Full Disk Access…", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .foregroundStyle(.orange)
            }
            HStack {
                Text("Macintosh HD").font(.caption.weight(.medium))
                Spacer()
                Text("\(m.diskFree.formattedBytes) free").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: m.diskFraction)
                .progressViewStyle(.linear)
                .tint(m.diskFraction > 0.9 ? .orange : .accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                Text("Welcome to Scrub").font(.title.weight(.semibold))
                Text("A free, open-source way to keep your Mac clean and fast.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 18) {
                row("eye", "Review before removing", "Nothing is deleted until you've seen it and confirmed.")
                row("lock.shield", "Careful by default", "System files, documents and apps you're using are never touched.")
                row("arrow.uturn.backward", "Easy to undo", "Apps, installers and leftovers go to the Trash first.")
            }
            .padding(.horizontal, 36)

            Divider().padding(.top, 26)

            HStack {
                if state.hasFullDiskAccess {
                    Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Button("Allow Full Disk Access…") { SystemAccess.openFullDiskAccessSettings() }
                }
                Spacer()
                Button("Continue", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
            .padding(20)
        }
        .frame(width: 480)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in state.refreshAccess() }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
