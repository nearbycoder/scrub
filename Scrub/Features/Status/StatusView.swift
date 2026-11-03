import SwiftUI

struct StatusView: View {
    @Environment(AppState.self) private var state
    @State private var sortOrder = [KeyPathComparator(\ProcessSample.cpu, order: .reverse)]
    @State private var selection: ProcessSample.ID?
    @State private var pendingKill: (ProcessSample, Bool)?

    private var m: SystemMonitor { state.monitor }

    var body: some View {
        VSplitView {
            ScrollView {
                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        cpu
                        memory
                        gpuOrDisk
                    }
                    GridRow {
                        disk
                        network
                        power
                    }
                }
                .padding(16)
            }
            .frame(minHeight: 260, idealHeight: 420)
            processes
                .frame(minHeight: 180)
        }
        .navigationTitle("Activity")
        .navigationSubtitle("Health \(m.healthScore) · \(m.healthSummary)")
        .onAppear { m.acquire("status"); m.acquire("processes") }
        .onDisappear { m.release("status"); m.release("processes") }
        .confirmationDialog("\(pendingKill?.1 == true ? "Force quit" : "Quit") “\(pendingKill?.0.name ?? "")”?",
                            isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } })) {
            Button(pendingKill?.1 == true ? "Force Quit" : "Quit", role: .destructive) {
                if let (p, force) = pendingKill { kill(p.pid, force ? SIGKILL : SIGTERM) }
                pendingKill = nil
            }
        } message: { Text("Unsaved changes in this process may be lost.") }
    }

    private func panel<Content: View>(_ title: String, _ symbol: String, value: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label(title, systemImage: symbol).font(.headline)
                    Spacer()
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(4)
        }
    }

    private var cpu: some View {
        panel("CPU", "cpu", value: m.cpuUsage.percent) {
            Sparkline(values: m.cpuHistory, color: .green, maxValue: 1).frame(height: 54)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(m.coreUsage.enumerated()), id: \.offset) { _, u in
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(.quaternary)
                        Rectangle().fill(u > 0.75 ? Color.orange : Color.green).frame(height: max(1, 22 * u))
                    }
                    .frame(height: 22)
                    .clipShape(.rect(cornerRadius: 1.5))
                }
            }
            Text(String(format: "%d cores · load %.2f, %.2f, %.2f", m.coreUsage.count, m.loadAverage.0, m.loadAverage.1, m.loadAverage.2))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var memory: some View {
        panel("Memory", "memorychip", value: m.memoryUsed.formattedBytes) {
            Sparkline(values: m.memoryHistory, color: m.memoryPressure >= 2 ? .orange : .purple, maxValue: 1).frame(height: 54)
            StorageBar(segments: [
                .init(id: "app", label: "App", bytes: m.memoryApp, color: .purple),
                .init(id: "wired", label: "Wired", bytes: m.memoryWired, color: .indigo),
                .init(id: "compressed", label: "Compressed", bytes: m.memoryCompressed, color: .pink),
            ], total: m.memoryTotal, height: 8)
            Text("Pressure \(m.pressureLabel.lowercased()) · swap \(m.swapUsed.formattedBytes) · \(m.memoryTotal.formattedBytes) installed")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var gpuOrDisk: some View {
        if let gpu = m.gpuUsage {
            panel("GPU", "square.stack.3d.up", value: gpu.percent) {
                Sparkline(values: m.gpuHistory, color: .orange, maxValue: 1).frame(height: 54)
                Text("Device utilization").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            panel("Thermal", "thermometer.medium", value: thermalLabel) {
                Text("macOS reports the thermal state as \(thermalLabel.lowercased()).").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var disk: some View {
        panel("Disk", "internaldrive", value: (m.diskReadRate + m.diskWriteRate).formattedRate) {
            Sparkline(values: m.diskHistory, color: .teal).frame(height: 54)
            HStack {
                Text("Read \(m.diskReadRate.formattedRate)")
                Text("Write \(m.diskWriteRate.formattedRate)")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Text("\(m.diskFree.formattedBytes) available of \(m.diskTotal.formattedBytes)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var network: some View {
        let peak = max(m.netDownHistory.max() ?? 0, m.netUpHistory.max() ?? 0, 16 * 1024)
        return panel("Network", "network", value: m.netDownRate.formattedRate) {
            ZStack {
                Sparkline(values: m.netDownHistory, color: .blue, maxValue: peak)
                Sparkline(values: m.netUpHistory, color: .orange, maxValue: peak)
            }
            .frame(height: 54)
            HStack(spacing: 12) {
                Label(m.netDownRate.formattedRate, systemImage: "arrow.down").foregroundStyle(.blue)
                Label(m.netUpRate.formattedRate, systemImage: "arrow.up").foregroundStyle(.orange)
            }
            .font(.caption).monospacedDigit()
        }
    }

    private var power: some View {
        panel(m.battery == nil ? "System" : "Battery", m.battery == nil ? "power" : "battery.75percent",
              value: m.battery.map { "\($0.level)%" } ?? m.uptime.uptimeDescription) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                if let b = m.battery {
                    GridRow { info("Status", b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in" : "On battery")); info("Health", b.health.map { "\($0)%" } ?? "—") }
                    GridRow { info("Cycles", b.cycleCount.map(String.init) ?? "—"); info("Power", b.watts.map { String(format: "%.1f W", $0) } ?? "—") }
                }
                GridRow { info("Thermal", thermalLabel); info("Uptime", m.uptime.uptimeDescription) }
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
            Text(value).font(.callout).monospacedDigit()
        }
    }

    // MARK: Processes

    private var processes: some View {
        Table(m.topProcesses.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Process", value: \.name) { p in
                HStack(spacing: 6) {
                    ProcessIcon(pid: p.pid)
                    Text(p.name).lineLimit(1)
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn("% CPU", value: \.cpu) { p in
                Text(p.cpu, format: .number.precision(.fractionLength(1))).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("Memory", value: \.memory) { p in SizeText(bytes: p.memory) }
                .width(min: 70, ideal: 90, max: 110)
            TableColumn("PID", value: \.pid) { p in
                Text(String(p.pid)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 60, max: 80)
            TableColumn("User", value: \.user) { p in Text(p.user).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 90, max: 130)
        }
        .contextMenu(forSelectionType: ProcessSample.ID.self) { ids in
            if let pid = ids.first, let p = m.topProcesses.first(where: { $0.pid == pid }) {
                Button("Copy Name") { SystemAccess.copyToPasteboard(p.name) }
                Button("Copy PID") { SystemAccess.copyToPasteboard(String(p.pid)) }
                Divider()
                Button("Quit…") { pendingKill = (p, false) }
                Button("Force Quit…", role: .destructive) { pendingKill = (p, true) }
            }
        }
        .overlay { if m.topProcesses.isEmpty { ProgressView() } }
    }
}

private struct ProcessIcon: View {
    let pid: Int32
    var body: some View {
        if let icon = ProcessIconCache.icon(for: pid) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "gearshape").foregroundStyle(.tertiary).frame(width: 16, height: 16)
        }
    }
}

enum ProcessIconCache {
    private static var cache: [Int32: NSImage?] = [:]
    static func icon(for pid: Int32) -> NSImage? {
        if let hit = cache[pid] { return hit }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? bundleIcon(for: pid)
        if cache.count > 2000 { cache.removeAll() }
        cache[pid] = icon
        return icon
    }

    /// Helpers and background processes inside an app bundle get the outermost app's icon.
    private static func bundleIcon(for pid: Int32) -> NSImage? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        return IconCache.icon(for: String(path[..<range.lowerBound]) + ".app")
    }
}
