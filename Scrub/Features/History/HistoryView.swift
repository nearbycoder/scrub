import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var confirmClear = false
    @State private var selection: HistoryEntry.ID?
    @State private var sortOrder = [KeyPathComparator(\HistoryEntry.date, order: .reverse)]

    var body: some View {
        let entries = state.history.entries
        Group {
            if entries.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath",
                                       description: Text("Cleanups, uninstalls and maintenance runs will appear here."))
            } else {
                HSplitView {
                    Table(entries.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("Date", value: \.date) { e in
                            Text(e.date, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary)
                        }
                        .width(min: 110, ideal: 140, max: 170)
                        TableColumn("Action", value: \.title) { e in
                            Label(e.title, systemImage: e.kind.symbol).lineLimit(1)
                        }
                        TableColumn("Items", value: \.itemCount) { e in
                            Text(e.itemCount.formatted()).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .width(min: 50, ideal: 60, max: 80)
                        TableColumn("Freed", value: \.bytesFreed) { e in
                            if e.bytesFreed > 0 {
                                SizeText(bytes: e.bytesFreed)
                            } else {
                                Text("—").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .width(min: 70, ideal: 90, max: 110)
                    }
                    .frame(minWidth: 440)
                    details.frame(minWidth: 260, idealWidth: 320)
                }
            }
        }
        .navigationTitle("History")
        .navigationSubtitle(entries.isEmpty ? "" : "\(state.history.totalFreed.formattedBytes) freed across \(entries.count.counted("run"))")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear History", systemImage: "trash") }
                    .disabled(entries.isEmpty)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { state.history.clear() }
        } message: { Text("This only removes the log. It doesn't restore anything.") }
    }

    @ViewBuilder private var details: some View {
        if let id = selection, let entry = state.history.entries.first(where: { $0.id == id }) {
            List {
                Section {
                    LabeledContent("Action", value: entry.kind.label)
                    LabeledContent("Date") { Text(entry.date, format: .dateTime) }
                    if entry.bytesFreed > 0 { LabeledContent("Space freed", value: entry.bytesFreed.formattedBytes) }
                }
                if !entry.details.isEmpty {
                    Section("Items") {
                        ForEach(entry.details, id: \.self) { path in
                            Text(path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                                .contextMenu { Button("Copy Path") { SystemAccess.copyToPasteboard(path) } }
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "list.bullet.rectangle",
                                   description: Text("Select a run to see what it removed."))
        }
    }
}
