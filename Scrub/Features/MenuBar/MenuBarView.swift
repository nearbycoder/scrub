import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    private var m: SystemMonitor { state.monitor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scrub").font(.headline)
                    Text("Health \(m.healthScore) · \(m.healthSummary)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Gauge(value: Double(m.healthScore), in: 0...100) { EmptyView() } currentValueLabel: {
                    Text("\(m.healthScore)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(m.healthScore >= 75 ? .green : .orange)
                .scaleEffect(0.7)
                .frame(width: 36, height: 36)
            }

            VStack(spacing: 10) {
                meter("CPU", m.cpuUsage.percent, m.cpuUsage, .green)
                meter("Memory", m.memoryUsed.formattedBytes, m.memoryFraction, m.memoryPressure >= 2 ? .orange : .purple)
                meter("Disk", "\(m.diskFree.formattedBytes) free", m.diskFraction, .blue)
                if let b = m.battery {
                    meter("Battery", "\(b.level)%", Double(b.level) / 100, b.level < 20 ? .red : .green)
                }
                HStack {
                    Label(m.netDownRate.formattedRate, systemImage: "arrow.down")
                    Spacer()
                    Label(m.netUpRate.formattedRate, systemImage: "arrow.up")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Smart Scan…", symbol: "sparkles") {
                    open(.clean)
                    if state.clean.phase == .idle || state.clean.phase == .finished { state.clean.scan() }
                }
                MenuRow(title: "Free Up Memory", symbol: "memorychip") { state.optimize.run(only: ["memory"]) }
                MenuRow(title: "Open Scrub", symbol: "macwindow") { open(.overview) }
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit Scrub") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { m.acquire("menubar") }
        .onDisappear { m.release("menubar") }
    }

    private func meter(_ title: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: min(1, max(0, fraction)))
                .progressViewStyle(.linear)
                .tint(color)
        }
    }

    private func open(_ section: AppSection) {
        state.section = section
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// A full-width, menu-like row that highlights on hover.
private struct MenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hovering ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
