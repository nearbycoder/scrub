import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Sidebar(selection: $state.section)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                SceneBackground(colors: state.section.colors)
                detail
                    .id(state.section)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            .animation(.smooth(duration: 0.35), value: state.section)
        }
        .onAppear { showOnboarding = !state.settings.hasCompletedOnboarding }
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
            ForEach(AppSection.groups, id: \.0) { group in
                Section {
                    ForEach(group.1) { section in
                        NavigationLink(value: section) {
                            Label {
                                HStack {
                                    Text(section.title)
                                    Spacer()
                                    badge(for: section)
                                }
                            } icon: {
                                IconBadge(symbol: section.symbol, colors: section.colors, size: 22)
                            }
                        }
                    }
                } header: {
                    if !group.0.isEmpty { Text(group.0) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    @ViewBuilder private func badge(for section: AppSection) -> some View {
        switch section {
        case .clean where state.clean.phase == .ready && state.clean.totalSelected > 0:
            Text(state.clean.totalSelected.formattedBytes).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        case .status:
            Text(state.monitor.cpuUsage.percent).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !state.hasFullDiskAccess {
                Button {
                    SystemAccess.openFullDiskAccessSettings()
                } label: {
                    Label("Grant Full Disk Access", systemImage: "lock.open.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
            }
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.monitor.diskFree.formattedBytes) free")
                        .font(.caption.weight(.semibold))
                    MeterBar(fraction: state.monitor.diskFraction, colors: AppSection.analyze.colors, height: 5)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            IconBadge(symbol: "bubbles.and.sparkles.fill", colors: AppSection.clean.colors, size: 88)
                .padding(.top, 10)
            VStack(spacing: 6) {
                Text("Welcome to Scrub").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("A free, open-source cleaner that keeps your Mac fast, tidy and private.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                row("eye.fill", "Preview everything", "Nothing is removed until you review it and press Clean.")
                row("lock.shield.fill", "Safe by design", "System files, documents and running apps are always skipped.")
                row("arrow.uturn.backward.circle.fill", "Undo-friendly", "Apps, installers and leftovers go to the Trash first.")
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))

            GlassCard(tint: .orange) {
                HStack(spacing: 14) {
                    Image(systemName: state.hasFullDiskAccess ? "checkmark.seal.fill" : "lock.open.fill")
                        .font(.title)
                        .foregroundStyle(state.hasFullDiskAccess ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.hasFullDiskAccess ? "Full Disk Access granted" : "Allow Full Disk Access").font(.headline)
                        Text("Lets Scrub measure Safari, Mail and app container caches. Add Scrub in System Settings, then come back.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !state.hasFullDiskAccess {
                        Button("Open Settings") { SystemAccess.openFullDiskAccessSettings() }
                            .buttonStyle(.glass)
                    }
                }
            }

            Button {
                onFinish()
            } label: {
                Text("Get Started").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(AppSection.clean.tint)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 520)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in state.refreshAccess() }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AppSection.clean.gradient).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// Scrollable page scaffold shared by every section.
struct Page<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
