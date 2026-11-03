import SwiftUI

struct PurgeView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    @State private var collapsed: Set<String> = []
    private var model: PurgeModel { state.purge }

    var body: some View {
        Page(spacing: 16) {
            SectionHeader(section: .purge) {
                Button { model.scan() } label: {
                    Label(model.projects.isEmpty ? "Scan Projects" : "Rescan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.glass)
                .disabled(model.isScanning)
            }
            rootsCard
            if let freed = model.lastFreed {
                ResultBanner(title: "Freed \(freed.formattedBytes)", message: "Build folders are recreated the next time you install or build.",
                             colors: AppSection.purge.colors) { model.lastFreed = nil }
            }
            if model.isScanning {
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        ScanningOrb(colors: AppSection.purge.colors, size: 150)
                        Text("Looking through \(model.scannedDirs.formatted()) folders…").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 30)
            } else if model.projects.isEmpty {
                GlassCard {
                    EmptyState(symbol: "shippingbox.fill", title: "Find stale build folders",
                               message: "node_modules, target, .build, DerivedData, venv and friends can add up to tens of gigabytes. Projects you touched in the last \(state.settings.purgeRecentDays) days stay unselected.",
                               colors: AppSection.purge.colors)
                }
            } else {
                ForEach(model.projects) { project in projectCard(project) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.projects.isEmpty {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.selectedSize.formattedBytes).font(.title3.bold().monospacedDigit()).contentTransition(.numericText())
                        Text("\(model.selectedArtifacts.count) of \(model.projects.flatMap(\.artifacts).count) folders").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { confirm = true } label: {
                        Label("Purge", systemImage: "shippingbox.and.arrow.backward.fill").font(.headline).padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppSection.purge.tint)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(model.selectedArtifacts.isEmpty || model.isPurging)
                }
                .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 18)
            }
        }
        .confirmationDialog("Purge \(model.selectedArtifacts.count) build folders?", isPresented: $confirm) {
            Button(state.settings.purgeRemovalMode == .trash ? "Move to Trash" : "Delete \(model.selectedSize.formattedBytes)", role: .destructive) { model.purge() }
        } message: {
            Text("These folders only hold generated files. Run your package manager or build again to restore them.")
        }
    }

    private var rootsCard: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(AppSection.purge.gradient)
                Text("Searching").foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.existingRoots, id: \.self) { root in Pill(text: Paths.abbreviate(root), color: .orange) }
                        if model.existingRoots.isEmpty { Text("No project folders found. Add one →").foregroundStyle(.secondary) }
                    }
                }
                Button("Add Folder…") { addRoot() }.buttonStyle(.glass)
            }
        }
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let p = Paths.abbreviate(url.path)
            if !state.settings.projectRoots.contains(p) { state.settings.projectRoots.append(p) }
        }
    }

    private func projectCard(_ project: ProjectArtifacts) -> some View {
        let allOn = project.artifacts.allSatisfy { !model.excluded.contains($0.path) }
        return GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(get: { allOn }, set: { on in
                        for a in project.artifacts { if on { model.excluded.remove(a.path) } else { model.excluded.insert(a.path) } }
                    }))
                    .toggleStyle(.checkbox).labelsHidden()
                    FileIcon(path: project.path, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name).font(.headline)
                        Text(Paths.abbreviate(project.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let d = project.lastActivity {
                        Pill(text: "Active \(d.relativeDescription)", color: d.daysAgo < state.settings.purgeRecentDays ? .green : .secondary)
                    }
                    Text(project.size.formattedBytes).font(.title3.weight(.semibold).monospacedDigit())
                }
                .padding(16)
                ForEach(project.artifacts) { artifact in
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(get: { !model.excluded.contains(artifact.path) }, set: { on in
                            if on { model.excluded.remove(artifact.path) } else { model.excluded.insert(artifact.path) }
                        }))
                        .toggleStyle(.checkbox).labelsHidden()
                        Image(systemName: "folder.fill").foregroundStyle(.orange)
                        Text(artifact.name).font(.callout.monospaced())
                        Text(artifact.kind).font(.caption).foregroundStyle(.secondary)
                        if artifact.path.dropFirst(project.path.count + 1).contains("/") {
                            Text(String(artifact.path.dropFirst(project.path.count + 1))).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(artifact.size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.leading, 26)
                    .padding(.vertical, 7)
                    .contextMenu { FileContextMenu(path: artifact.path) }
                }
            }
        }
    }
}
