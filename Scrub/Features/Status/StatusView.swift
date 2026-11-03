import SwiftUI

struct StatusView: View {
    @Environment(AppState.self) private var state
    @State private var sortByMemory = false
    @State private var pendingKill: (ProcessSample, Bool)?

    private var m: SystemMonitor { state.monitor }

    var body: some View {
        Page(spacing: 16) {
            SectionHeader(section: .status) {
                HStack(spacing: 10) {
                    RingGauge(progress: Double(m.healthScore) / 100, colors: healthColors, lineWidth: 6) {
                        Text("\(m.healthScore)").font(.headline.monospacedDigit())
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Health").font(.caption).foregroundStyle(.secondary)
                        Text(m.healthSummary).font(.headline)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                cpuCard
                memoryCard
                diskCard
                networkCard
                if m.gpuUsage != nil { gpuCard }
                powerCard
            }
            processes
        }
        .onAppear { m.processesEnabled = true }
        .onDisappear { m.processesEnabled = false }
        .confirmationDialog("\(pendingKill?.1 == true ? "Force quit" : "Quit") \(pendingKill?.0.name ?? "")?",
                            isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })) {
            Button(pendingKill?.1 == true ? "Force Quit" : "Quit", role: .destructive) {
                if let (p, force) = pendingKill { kill(p.pid, force ? SIGKILL : SIGTERM) }
                pendingKill = nil
            }
        } message: { Text("Unsaved changes in this process may be lost.") }
    }

    private var healthColors: [Color] {
        m.healthScore >= 75 ? [.green, .teal] : m.healthScore >= 55 ? [.yellow, .orange] : [.orange, .red]
    }

    private func card<Content: View>(_ title: String, _ symbol: String, _ colors: [Color], value: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconBadge(symbol: symbol, colors: colors, size: 28)
                Text(title).font(.headline)
                Spacer()
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var cpuCard: some View {
        card("CPU", "cpu.fill", [.green, .teal], value: m.cpuUsage.percent) {
            Sparkline(values: m.cpuHistory, color: .teal, maxValue: 1).frame(height: 60)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(m.coreUsage.enumerated()), id: \.offset) { _, u in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.07))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.teal, u > 0.7 ? .orange : .green], startPoint: .bottom, endPoint: .top))
                            .frame(height: max(2, 30 * u))
                    }
                    .frame(maxWidth: 14, maxHeight: 30)
                }
            }
            .frame(height: 30)
            .animation(.smooth, value: m.coreUsage)
            Text(String(format: "%d cores · load %.2f  %.2f  %.2f", m.coreUsage.count, m.loadAverage.0, m.loadAverage.1, m.loadAverage.2))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var memoryCard: some View {
        card("Memory", "memorychip.fill", [.purple, .indigo], value: m.memoryFraction.percent) {
            Sparkline(values: m.memoryHistory, color: .purple, maxValue: 1).frame(height: 60)
            GeometryReader { geo in
                let total = max(1, Double(m.memoryTotal))
                HStack(spacing: 2) {
                    ForEach(Array([(m.memoryApp, Color.purple), (m.memoryWired, .indigo), (m.memoryCompressed, .pink)].enumerated()), id: \.offset) { _, seg in
                        Rectangle().fill(seg.1).frame(width: max(0, geo.size.width * Double(seg.0) / total))
                    }
                    Rectangle().fill(.primary.opacity(0.1))
                }
            }
            .frame(height: 8)
            .clipShape(.capsule)
            HStack(spacing: 12) {
                legend("App", m.memoryApp, .purple)
                legend("Wired", m.memoryWired, .indigo)
                legend("Compressed", m.memoryCompressed, .pink)
            }
            Text("\(m.memoryUsed.formattedBytes) of \(m.memoryTotal.formattedBytes) · Pressure \(m.pressureLabel) · Swap \(m.swapUsed.formattedBytes)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func legend(_ label: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(bytes.formattedBytes)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var diskCard: some View {
        card("Disk", "internaldrive.fill", AppSection.analyze.colors, value: m.diskFraction.percent) {
            Sparkline(values: m.diskHistory, color: .blue).frame(height: 60)
            MeterBar(fraction: m.diskFraction, colors: AppSection.analyze.colors)
            HStack {
                Label(m.diskReadRate.formattedRate, systemImage: "arrow.down.doc").font(.caption.monospacedDigit())
                Label(m.diskWriteRate.formattedRate, systemImage: "arrow.up.doc").font(.caption.monospacedDigit())
                Spacer()
            }
            .foregroundStyle(.secondary)
            Text("\(m.diskFree.formattedBytes) available of \(m.diskTotal.formattedBytes)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var networkCard: some View {
        card("Network", "network", [.blue, .cyan], value: m.netDownRate.formattedRate) {
            ZStack {
                Sparkline(values: m.netDownHistory, color: .cyan, maxValue: max(m.netDownHistory.max() ?? 1, m.netUpHistory.max() ?? 1, 1024))
                Sparkline(values: m.netUpHistory, color: .orange, maxValue: max(m.netDownHistory.max() ?? 1, m.netUpHistory.max() ?? 1, 1024))
                    .opacity(0.8)
            }
            .frame(height: 80)
            HStack(spacing: 16) {
                Label("Down \(m.netDownRate.formattedRate)", systemImage: "arrow.down").foregroundStyle(.cyan)
                Label("Up \(m.netUpRate.formattedRate)", systemImage: "arrow.up").foregroundStyle(.orange)
            }
            .font(.caption.monospacedDigit())
        }
    }

    private var gpuCard: some View {
        card("GPU", "square.stack.3d.up.fill", [.orange, .pink], value: (m.gpuUsage ?? 0).percent) {
            Sparkline(values: m.gpuHistory, color: .pink, maxValue: 1).frame(height: 100)
        }
    }

    private var powerCard: some View {
        card(m.battery == nil ? "System" : "Battery", m.battery?.isCharging == true ? "battery.100.bolt" : "bolt.fill",
             [.yellow, .orange], value: m.battery.map { "\($0.level)%" } ?? m.uptime.uptimeDescription) {
            VStack(alignment: .leading, spacing: 8) {
                if let b = m.battery {
                    MeterBar(fraction: Double(b.level) / 100, colors: b.level < 20 ? [.red, .orange] : [.yellow, .green], height: 10)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { info("Status", b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in" : "On battery")); info("Health", b.health.map { "\($0)%" } ?? "—") }
                        GridRow { info("Cycles", b.cycleCount.map(String.init) ?? "—"); b.temperature.map { info("Temp", String(format: "%.1f °C", $0)) } ?? info("Condition", b.condition ?? "Normal") }
                        GridRow { info("Power", b.watts.map { String(format: "%.1f W", $0) } ?? "—"); info("Remaining", b.timeRemaining.map { "\($0 / 60)h \($0 % 60)m" } ?? "—") }
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { info("Thermal", thermalLabel); info("Uptime", m.uptime.uptimeDescription) }
                }
            }
        }
    }

    private var thermalLabel: String {
        switch m.thermalState {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "—"
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
    }

    // MARK: Processes

    private var processes: some View {
        let list = sortByMemory ? m.topProcesses.sorted { $0.memory > $1.memory } : m.topProcesses
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top Processes").font(.headline)
                Spacer()
                Picker("", selection: $sortByMemory) {
                    Text("CPU").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
            .padding(18)
            Divider()
            if list.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(30)
            }
            ForEach(list.prefix(12)) { p in
                HStack(spacing: 12) {
                    processIcon(p)
                    Text(p.name).lineLimit(1)
                    Text("\(p.pid)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Spacer()
                    MeterBar(fraction: min(1, p.cpu / 100), colors: [.green, .teal], height: 5).frame(width: 80)
                    Text(String(format: "%.1f%%", p.cpu)).font(.callout.monospacedDigit()).frame(width: 60, alignment: .trailing)
                    Text(p.memory.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .contextMenu {
                    Button("Copy Name") { SystemAccess.copyToPasteboard(p.name) }
                    Button("Copy PID") { SystemAccess.copyToPasteboard("\(p.pid)") }
                    Divider()
                    Button("Quit…") { pendingKill = (p, false) }
                    Button("Force Quit…", role: .destructive) { pendingKill = (p, true) }
                }
            }
        }
        .padding(.bottom, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .animation(.smooth, value: list.map(\.pid))
    }

    @ViewBuilder private func processIcon(_ p: ProcessSample) -> some View {
        if let app = NSRunningApplication(processIdentifier: p.pid), let icon = app.icon {
            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
        } else {
            Image(systemName: "gearshape").frame(width: 20, height: 20).foregroundStyle(.secondary)
        }
    }
}
