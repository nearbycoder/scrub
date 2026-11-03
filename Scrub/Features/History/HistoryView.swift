import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var confirmClear = false
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Page(spacing: 16) {
            SectionHeader(section: .history) {
                if !state.history.entries.isEmpty {
                    Button("Clear History", role: .destructive) { confirmClear = true }.buttonStyle(.glass)
                }
            }
            if state.history.entries.isEmpty {
                GlassCard {
                    EmptyState(symbol: "clock.arrow.circlepath", title: "Nothing yet",
                               message: "Each cleanup, uninstall and maintenance run is recorded here so you always know what changed.",
                               colors: AppSection.history.colors)
                }
            } else {
                summary
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(state.history.entries) { entry in
                            row(entry)
                            if entry.id != state.history.entries.last?.id { Divider().padding(.leading, 62) }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { state.history.clear() }
        }
    }

    private var summary: some View {
        let entries = state.history.entries
        let daily = Dictionary(grouping: entries.filter { $0.date > Date().addingTimeInterval(-30 * 86_400) }) {
            Calendar.current.startOfDay(for: $0.date)
        }.map { (day: $0.key, bytes: $0.value.reduce(0) { $0 + $1.bytesFreed }) }.sorted { $0.day < $1.day }
        return HStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Freed all-time").font(.subheadline).foregroundStyle(.secondary)
                    let parts = state.history.totalFreed.byteParts
                    BigNumber(value: parts.0, unit: parts.1, size: 40)
                    Text("\(entries.count) runs since \(entries.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 280)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 30 days").font(.subheadline).foregroundStyle(.secondary)
                    Chart(daily, id: \.day) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Freed", Double(d.bytes) / 1_000_000_000))
                            .foregroundStyle(AppSection.clean.gradient)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text("\(d, specifier: "%.1f") GB") } } } }
                    .frame(height: 90)
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let isOpen = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                IconBadge(symbol: entry.kind.symbol, colors: colors(for: entry.kind), size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                    Text("\(entry.kind.label) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.bytesFreed > 0 {
                    Text(entry.bytesFreed.formattedBytes).font(.callout.weight(.semibold).monospacedDigit())
                }
                if !entry.details.isEmpty {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.smooth) { if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) } }
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.details.prefix(100), id: \.self) { d in
                        Text(d).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if entry.details.count > 100 { Text("and \(entry.details.count - 100) more").font(.caption).foregroundStyle(.tertiary) }
                }
                .padding(.leading, 62)
                .padding(.trailing, 16)
                .padding(.bottom, 10)
            }
        }
    }

    private func colors(for kind: HistoryEntry.Kind) -> [Color] {
        switch kind {
        case .clean: AppSection.clean.colors
        case .uninstall: AppSection.uninstall.colors
        case .analyze: AppSection.analyze.colors
        case .optimize: AppSection.optimize.colors
        case .purge: AppSection.purge.colors
        case .installers: AppSection.installers.colors
        }
    }
}
