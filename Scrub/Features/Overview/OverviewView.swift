import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                storage
                metrics
                recommendations
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.section = .clean
                    if state.clean.phase != .scanning { state.clean.scan() }
                } label: {
                    Label("Smart Scan", systemImage: "sparkles")
                }
                .help("Scan for junk files")
            }
        }
        .onAppear { state.monitor.acquire("overview") }
        .onDisappear { state.monitor.release("overview") }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: MacInfo.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(MacInfo.productName).font(.title2.weight(.semibold))
                Text([MacInfo.chip, "\(MacInfo.memory.formattedBytes) memory", MacInfo.osDescription].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                Text("Up for \(state.monitor.uptime.uptimeDescription)")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var storage: some View {
        let m = state.monitor
        let junk = state.clean.phase == .ready ? min(state.clean.totalFound, m.diskUsed) : 0
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Macintosh HD", systemImage: "internaldrive").font(.headline)
                    Spacer()
                    Text("\(m.diskFree.formattedBytes) available of \(m.diskTotal.formattedBytes)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                StorageBar(segments: [
                    .init(id: "used", label: "Used", bytes: m.diskUsed - junk, color: .accentColor),
                    .init(id: "junk", label: "Can be cleaned", bytes: junk, color: .orange),
                    .init(id: "purgeable", label: "Purgeable", bytes: min(m.diskPurgeable, m.diskFree), color: .gray.opacity(0.6)),
                ], total: m.diskTotal)
            }
            .padding(6)
        }
    }

    private var metrics: some View {
        let m = state.monitor
        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                MetricTile(title: "CPU", symbol: "cpu", value: m.cpuUsage.percent,
                           detail: String(format: "Load %.2f", m.loadAverage.0), color: .green,
                           history: m.cpuHistory, maxValue: 1)
                MetricTile(title: "Memory", symbol: "memorychip", value: m.memoryUsed.formattedBytes,
                           detail: "Pressure \(m.pressureLabel.lowercased())",
                           color: m.memoryPressure >= 2 ? .orange : .purple, history: m.memoryHistory, maxValue: 1)
                MetricTile(title: "Network", symbol: "network", value: m.netDownRate.formattedRate,
                           detail: "Up \(m.netUpRate.formattedRate)", color: .blue, history: m.netDownHistory)
                if let b = m.battery {
                    MetricTile(title: "Battery", symbol: b.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                               value: "\(b.level)%",
                               detail: [b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in" : "On battery"),
                                        b.health.map { "\($0)% health" }].compactMap { $0 }.joined(separator: " · "),
                               color: .green, history: [])
                } else {
                    MetricTile(title: "Disk", symbol: "internaldrive", value: (m.diskReadRate + m.diskWriteRate).formattedRate,
                               detail: "Read and write", color: .teal, history: m.diskHistory)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { state.section = .status }
    }

    private var recommendations: some View {
        GroupBox {
            VStack(spacing: 0) {
                let items = recommendationItems
                ForEach(items.indices, id: \.self) { index in
                    items[index]
                    if index < items.count - 1 { Divider().padding(.leading, 44) }
                }
            }
        } label: {
            Text("Recommendations").font(.headline).padding(.bottom, 4)
        }
    }

    private var recommendationItems: [RecommendationRow] {
        let m = state.monitor
        var rows: [RecommendationRow] = []
        switch state.clean.phase {
        case .idle:
            rows.append(.init(symbol: "sparkles", color: .accentColor, title: "Look for junk files",
                              detail: "Caches, logs, developer data and leftovers you can safely remove.",
                              action: "Scan") { state.section = .clean; state.clean.scan() })
        case .scanning:
            rows.append(.init(symbol: "sparkles", color: .accentColor, title: "Scanning for junk…",
                              detail: "\(state.clean.scannedBytes.formattedBytes) checked so far.", isBusy: true))
        case .ready:
            rows.append(.init(symbol: "sparkles", color: .orange, title: "\(state.clean.totalSelected.formattedBytes) can be cleaned",
                              detail: "\(state.clean.selectedItemCount) items selected across \(state.clean.results.filter(\.isActive).count) categories.",
                              action: "Review") { state.section = .clean })
        case .cleaning:
            rows.append(.init(symbol: "sparkles", color: .accentColor, title: "Cleaning…", detail: state.clean.currentStep, isBusy: true))
        case .finished:
            rows.append(.init(symbol: "checkmark.circle", color: .green, title: "Freed \(state.clean.lastFreed.formattedBytes)",
                              detail: "Your last cleanup finished \(state.clean.lastScanDate?.relativeDescription ?? "recently").",
                              action: "Scan Again") { state.section = .clean; state.clean.scan() })
        }
        if state.purge.projects.isEmpty {
            rows.append(.init(symbol: "hammer", color: .indigo, title: "Find old build folders",
                              detail: "node_modules, DerivedData and other build output often add up to gigabytes.",
                              action: "Open") { state.section = .purge })
        } else {
            rows.append(.init(symbol: "hammer", color: .indigo, title: "\(state.purge.totalSize.formattedBytes) in build folders",
                              detail: "Across \(state.purge.projects.count) projects.", action: "Review") { state.section = .purge })
        }
        if m.diskFraction > 0.85 {
            rows.append(.init(symbol: "internaldrive", color: .orange, title: "Your startup disk is \(m.diskFraction.percent) full",
                              detail: "Space Lens shows what's taking up the most room.", action: "Open") { state.section = .analyze })
        }
        if m.memoryPressure >= 2 {
            rows.append(.init(symbol: "memorychip", color: .orange, title: "Memory pressure is \(m.pressureLabel.lowercased())",
                              detail: "Quit apps you aren't using, or free inactive memory.", action: "Activity") { state.section = .status })
        }
        if m.uptime > 7 * 86_400 {
            rows.append(.init(symbol: "arrow.counterclockwise", color: .secondary, title: "Restart when you get a chance",
                              detail: "Your Mac has been running for \(Int(m.uptime / 86_400)) days. A restart clears memory and finishes updates."))
        }
        if let h = m.battery?.health, h < 80 {
            rows.append(.init(symbol: "battery.25percent", color: .orange, title: "Battery health is \(h)%",
                              detail: "Your battery may need service soon."))
        }
        if !state.hasFullDiskAccess {
            rows.append(.init(symbol: "lock.shield", color: .orange, title: "Allow Full Disk Access",
                              detail: "Needed to clean Safari, Mail and other apps' caches.",
                              action: "Open Settings…") { SystemAccess.openFullDiskAccessSettings() })
        }
        return rows
    }
}

struct RecommendationRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    var action: String? = nil
    var isBusy = false
    var perform: (() -> Void)? = nil

    init(symbol: String, color: Color, title: String, detail: String, action: String? = nil,
         isBusy: Bool = false, perform: (() -> Void)? = nil) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.detail = detail
        self.action = action
        self.isBusy = isBusy
        self.perform = perform
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if isBusy {
                ProgressView().controlSize(.small)
            } else if let action, let perform {
                Button(action, action: perform)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

struct MetricTile: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let color: Color
    let history: [Double]
    var maxValue: Double? = nil

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Group {
                    if history.count > 2 {
                        Sparkline(values: history, color: color, maxValue: maxValue)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 30)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}
