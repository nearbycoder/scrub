import SwiftUI

struct OptimizeView: View {
    @Environment(AppState.self) private var state
    private var model: OptimizeModel { state.optimize }

    var body: some View {
        Form {
            if let date = model.finishedAt {
                Section {
                    let done = model.status.values.filter { if case .done = $0 { return true }; return false }.count
                    Label("\(done) tasks finished \(date.relativeDescription).", systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
            Section {
                Toggle(isOn: Binding(get: { model.touchIDEnabled }, set: { model.setTouchID($0) })) {
                    Text("Use Touch ID for sudo")
                    Text("Approve sudo in Terminal with your fingerprint. The setting is kept in /etc/pam.d/sudo_local, so it survives macOS updates.")
                }
                .disabled(model.touchIDBusy)
            } header: {
                Text("Security")
            }
            Section {
                ForEach(model.availableTasks.filter { !$0.requiresAdmin }) { TaskRow(task: $0) }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("These run as you and don't need a password.").foregroundStyle(.secondary)
            }
            Section {
                ForEach(model.availableTasks.filter(\.requiresAdmin)) { TaskRow(task: $0) }
            } header: {
                Text("Requires Administrator")
            } footer: {
                Text("You'll be asked for your password once for all selected tasks.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Maintenance")
        .navigationSubtitle("\(selectedCount) of \(model.availableTasks.count) tasks selected")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.run()
                } label: {
                    if model.isRunning { ProgressView().controlSize(.small) } else { Text("Run Tasks") }
                }
                .buttonStyle(.glassProminent)
                .disabled(model.isRunning || selectedCount == 0)
            }
        }
    }

    private var selectedCount: Int { model.availableTasks.filter { model.selected.contains($0.id) }.count }
}

private struct TaskRow: View {
    @Environment(AppState.self) private var state
    let task: OptimizeTask

    var body: some View {
        let model = state.optimize
        LabeledContent {
            HStack(spacing: 10) {
                if let status = model.status[task.id] { StatusLabel(status: status) }
                Toggle("", isOn: Binding(get: { model.selected.contains(task.id) }, set: { on in
                    if on { model.selected.insert(task.id) } else { model.selected.remove(task.id) }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.isRunning)
            }
        } label: {
            Label {
                Text(task.title)
                Text(task.detail)
            } icon: {
                Image(systemName: task.symbol).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusLabel: View {
    let status: OptimizeStatus

    var body: some View {
        Group {
            switch status {
            case .pending: Text("Waiting").foregroundStyle(.secondary)
            case .running: ProgressView().controlSize(.small)
            case .done(let m): Label(m, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .skipped(let m): Label(m, systemImage: "minus.circle").foregroundStyle(.orange)
            case .failed(let m): Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red).help(m)
            }
        }
        .font(.callout)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }
}
