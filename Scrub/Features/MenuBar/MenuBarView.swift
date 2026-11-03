import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    private var m: SystemMonitor { state.monitor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: "bubbles.and.sparkles.fill", colors: AppSection.clean.colors, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Scrub").font(.headline)
                    Text("Health \(m.healthScore) · \(m.healthSummary)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                RingGauge(progress: Double(m.healthScore) / 100, colors: [.green, .teal], lineWidth: 4) {
                    Text("\(m.healthScore)").font(.caption2.bold().monospacedDigit())
                }
                .frame(width: 32, height: 32)
            }

            GlassEffectContainer(spacing: 8) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        tile("CPU", m.cpuUsage.percent, "cpu.fill", .teal, m.cpuHistory, 1)
                        tile("Memory", m.memoryFraction.percent, "memorychip.fill", .purple, m.memoryHistory, 1)
                    }
                    GridRow {
                        tile("Down", m.netDownRate.formattedRate, "arrow.down", .cyan, m.netDownHistory, nil)
                        tile("Disk free", m.diskFree.formattedBytes, "internaldrive.fill", .blue, [], nil)
                    }
                }
            }

            if let b = m.battery {
                HStack {
                    Image(systemName: b.isCharging ? "battery.100.bolt" : "battery.75")
                    Text("\(b.level)%").monospacedDigit()
                    Spacer()
                    if let h = b.health { Text("Health \(h)%").foregroundStyle(.secondary) }
                    if let c = b.cycleCount { Text("· \(c) cycles").foregroundStyle(.secondary) }
                }
                .font(.caption)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    open(.clean)
                    if state.clean.phase == .idle || state.clean.phase == .finished { state.clean.scan() }
                } label: { Label("Smart Scan", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent)
                .tint(AppSection.clean.tint)
                Button { state.optimize.run(only: ["memory"]) } label: {
                    Label("Free RAM", systemImage: "memorychip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            HStack {
                Button("Open Scrub") { open(.overview) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func tile(_ title: String, _ value: String, _ symbol: String, _ color: Color, _ history: [Double], _ max: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if history.count > 1 {
                Sparkline(values: history, color: color, maxValue: max).frame(height: 20)
            } else {
                Spacer().frame(height: 20)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func open(_ section: AppSection) {
        state.section = section
        openWindow(id: "main")
        NSApp.activate()
    }
}
