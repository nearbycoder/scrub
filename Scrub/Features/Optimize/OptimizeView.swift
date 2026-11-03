import SwiftUI

struct OptimizeView: View {
    @Environment(AppState.self) private var state
    private var model: OptimizeModel { state.optimize }

    var body: some View {
        Page {
            SectionHeader(section: .optimize) {
                Button {
                    model.run()
                } label: {
                    Label(model.isRunning ? "Running…" : "Run \(selectedCount) Tasks", systemImage: "bolt.fill")
                        .font(.headline).padding(.horizontal, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(AppSection.optimize.tint)
                .controlSize(.large)
                .disabled(model.isRunning || selectedCount == 0)
            }
            if let date = model.finishedAt {
                let done = model.status.values.filter { if case .done = $0 { return true }; return false }.count
                ResultBanner(title: "Maintenance complete", message: "\(done) tasks finished \(date.relativeDescription).",
                             colors: AppSection.optimize.colors) { model.finishedAt = nil; model.status = [:] }
            }
            touchIDCard
            taskSection(title: "Runs as you", subtitle: "No password needed.", tasks: model.availableTasks.filter { !$0.requiresAdmin })
            taskSection(title: "Needs administrator approval", subtitle: "You'll be asked for your password once for all of these.",
                        tasks: model.availableTasks.filter(\.requiresAdmin))
        }
    }

    private var selectedCount: Int { model.availableTasks.filter { model.selected.contains($0.id) }.count }

    private var touchIDCard: some View {
        GlassCard(tint: .pink) {
            HStack(spacing: 16) {
                IconBadge(symbol: "touchid", colors: [.pink, .red], size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Touch ID for sudo").font(.headline)
                    Text("Approve `sudo` in Terminal with your fingerprint instead of typing your password. Survives macOS updates.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.touchIDBusy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(get: { model.touchIDEnabled }, set: { model.setTouchID($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(model.touchIDBusy)
            }
        }
    }

    private func taskSection(title: String, subtitle: String, tasks: [OptimizeTask]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                ForEach(tasks) { task in taskCard(task) }
            }
        }
    }

    private func taskCard(_ task: OptimizeTask) -> some View {
        let isOn = model.selected.contains(task.id)
        return HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: task.symbol, colors: [task.tint.opacity(0.7), task.tint], size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title).font(.headline)
                    if task.requiresAdmin { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text(task.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let status = model.status[task.id] { statusLabel(status) }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: { on in
                if on { model.selected.insert(task.id) } else { model.selected.remove(task.id) }
            }))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(model.isRunning)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .glassEffect(isOn ? .regular.tint(task.tint.opacity(0.1)) : .regular, in: .rect(cornerRadius: 22))
        .animation(.smooth, value: isOn)
    }

    @ViewBuilder private func statusLabel(_ status: OptimizeStatus) -> some View {
        switch status {
        case .pending: Label("Waiting", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        case .running: HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Running…").font(.caption) }
        case .done(let m): Label(m, systemImage: "checkmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.green)
        case .skipped(let m): Label(m, systemImage: "forward.fill").font(.caption).foregroundStyle(.orange)
        case .failed(let m): Label(m, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }
}
