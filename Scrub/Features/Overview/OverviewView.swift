import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Page {
            SectionHeader(section: .overview, title: greeting, subtitle: Host.current().localizedName.map { "\($0) · macOS \(osVersion)" } ?? "macOS \(osVersion)")
            hero
            statsRow
            if !state.monitor.issues.isEmpty { issues }
            toolsGrid
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    // MARK: Hero

    private var hero: some View {
        let monitor = state.monitor
        return GlassCard(padding: 28, cornerRadius: 32) {
            HStack(spacing: 36) {
                RingGauge(progress: monitor.diskFraction, colors: AppSection.analyze.colors, lineWidth: 20) {
                    VStack(spacing: 0) {
                        let parts = monitor.diskFree.byteParts
                        BigNumber(value: parts.0, unit: parts.1, size: 30)
                        Text("available").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 170, height: 170)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Macintosh HD").font(.headline).foregroundStyle(.secondary)
                        Text("\(monitor.diskUsed.formattedBytes) of \(monitor.diskTotal.formattedBytes) used")
                            .font(.title2.weight(.semibold))
                    }
                    HStack(spacing: 10) {
                        Pill(text: "Health \(monitor.healthScore)", color: healthColor, symbol: "heart.fill")
                        Pill(text: monitor.healthSummary, color: healthColor)
                        if state.history.totalFreed > 0 {
                            Pill(text: "\(state.history.totalFreed.formattedBytes) freed all-time", color: .teal, symbol: "sparkles")
                        }
                    }
                    Text("Scrub checks caches, logs, developer junk, browser data, old installers and leftovers from apps you've removed.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                scanPanel.frame(width: 250)
            }
        }
    }

    private var healthColor: Color {
        switch state.monitor.healthScore {
        case 90...: .green
        case 75..<90: .teal
        case 55..<75: .orange
        default: .red
        }
    }

    @ViewBuilder private var scanPanel: some View {
        let clean = state.clean
        VStack(spacing: 14) {
            switch clean.phase {
            case .idle:
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(AppSection.clean.gradient)
                Button {
                    clean.scan()
                } label: {
                    Label("Smart Scan", systemImage: "sparkles").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(AppSection.clean.tint)
                .controlSize(.extraLarge)
            case .scanning:
                ScanningOrb(colors: AppSection.clean.colors, progress: clean.progress, size: 110)
                Text("Scanning \(clean.currentStep)…").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            case .ready:
                let parts = clean.totalSelected.byteParts
                BigNumber(value: parts.0, unit: parts.1, size: 40)
                Text("ready to clean").foregroundStyle(.secondary)
                HStack {
                    Button("Review") { state.section = .clean }.buttonStyle(.glass)
                    Button("Clean") { clean.clean() }.buttonStyle(.glassProminent).tint(AppSection.clean.tint)
                        .disabled(clean.totalSelected == 0)
                }
                .controlSize(.large)
            case .cleaning:
                ScanningOrb(colors: AppSection.clean.colors, progress: clean.progress, size: 110)
                Text("Cleaning…").foregroundStyle(.secondary)
            case .finished:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 46)).foregroundStyle(.green)
                Text("Freed \(clean.lastFreed.formattedBytes)").font(.title3.bold())
                Button("Scan Again") { clean.scan() }.buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stats

    private var statsRow: some View {
        let m = state.monitor
        return HStack(spacing: 16) {
            StatTile(title: "CPU", value: m.cpuUsage.percent, detail: String(format: "Load %.2f", m.loadAverage.0),
                     symbol: "cpu.fill", colors: [.green, .teal], history: m.cpuHistory, maxValue: 1)
            StatTile(title: "Memory", value: m.memoryUsed.formattedBytes, detail: "Pressure \(m.pressureLabel.lowercased())",
                     symbol: "memorychip.fill", colors: [.purple, .indigo], history: m.memoryHistory, maxValue: 1)
            StatTile(title: "Network", value: m.netDownRate.formattedRate, detail: "↑ \(m.netUpRate.formattedRate)",
                     symbol: "arrow.down.circle.fill", colors: [.blue, .cyan], history: m.netDownHistory)
            if let b = m.battery {
                StatTile(title: "Battery", value: "\(b.level)%", detail: [b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in" : "On battery"), b.health.map { "health \($0)%" }].compactMap { $0 }.joined(separator: " · "),
                         symbol: b.isCharging ? "battery.100.bolt" : "battery.75", colors: [.yellow, .orange], history: [], maxValue: 1)
            } else {
                StatTile(title: "Uptime", value: m.uptime.uptimeDescription, detail: "Since last restart",
                         symbol: "clock.fill", colors: [.orange, .pink], history: [], maxValue: 1)
            }
        }
        .onTapGesture { state.section = .status }
    }

    private var issues: some View {
        GlassCard(tint: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Worth a look", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                ForEach(state.monitor.issues, id: \.self) { issue in
                    Label(issue, systemImage: "circle.fill").font(.callout).labelStyle(BulletLabelStyle())
                }
            }
        }
    }

    // MARK: Tools

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools").font(.title3.bold()).padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach([AppSection.uninstall, .analyze, .optimize, .purge, .installers, .status], id: \.self) { section in
                    Button { state.section = section } label: {
                        HStack(spacing: 14) {
                            IconBadge(symbol: section.symbol, colors: section.colors, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title).font(.headline).foregroundStyle(.primary)
                                Text(section.subtitle).font(.callout).foregroundStyle(.secondary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                        .contentShape(.rect(cornerRadius: 22))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let colors: [Color]
    let history: [Double]
    var maxValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Group {
                if history.count > 1 {
                    Sparkline(values: history, color: colors[1], maxValue: maxValue)
                } else {
                    Color.clear
                }
            }
            .frame(height: 34)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}
