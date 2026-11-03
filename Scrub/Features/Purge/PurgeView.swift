import SwiftUI

struct PurgeView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    @State private var expanded: Set<String> = []
    @State private var selection = Set<String>()

    private var model: PurgeModel { state.purge }

    var body: some View {
        content
            .navigationTitle("Project Purge")
            .navigationSubtitle(model.existingRoots.map(Paths.abbreviate).joined(separator: ", "))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { addRoot() } label: { Label("Add Folder", systemImage: "folder.badge.plus") }
                        .help("Add a folder to search for projects")
                    Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.isScanning || model.isPurging)
                }
            }
            .confirmationDialog("Remove \(model.selectedArtifacts.count) build folders?", isPresented: $confirm) {
                Button(state.settings.purgeRemovalMode == .trash ? "Move to Trash" : "Delete \(model.selectedSize.formattedBytes)", role: .destructive) {
                    model.purge()
                }
            } message: {
                Text("They only contain generated files. Install or build the project again to restore them.")
            }
    }

    @ViewBuilder private var content: some View {
        if model.isScanning {
            ScanningPlaceholder(title: "Finding Build Folders", symbol: "hammer",
                                detail: "\(model.scannedDirs.formatted()) folders checked")
        } else if model.projects.isEmpty {
            ContentUnavailableView {
                Label("Project Purge", systemImage: "hammer")
            } description: {
                if let freed = model.lastFreed {
                    Text("Freed \(freed.formattedBytes). Nothing else to remove.")
                } else if model.existingRoots.isEmpty {
                    Text("Add the folder where you keep your code to find node_modules, build, target, DerivedData and other generated folders.")
                } else {
                    Text("Find node_modules, build, target, .build, DerivedData and other generated folders. Projects you've worked on in the last \(state.settings.purgeRecentDays) days stay unselected.")
                }
            } actions: {
                if model.existingRoots.isEmpty {
                    Button("Add Folder…") { addRoot() }.buttonStyle(.glassProminent).controlSize(.large)
                } else {
                    Button("Scan Projects") { model.scan() }.buttonStyle(.glassProminent).controlSize(.large)
                }
            }
        } else {
            table
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ActionBar {
                        SelectionSummary(bytes: model.selectedSize,
                                         detail: "\(model.selectedArtifacts.count) of \(model.projects.flatMap(\.artifacts).count) folders")
                    } actions: {
                        Button { confirm = true } label: { Text("Remove").padding(.horizontal, 10) }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(model.selectedArtifacts.isEmpty || model.isPurging)
                    }
                }
                .onAppear { expanded = Set(model.projects.prefix(12).map(\.id)) }
        }
    }

    private struct Row: Identifiable, Hashable {
        let id: String
        let project: ProjectArtifacts
        let artifact: BuildArtifact?
    }

    private var table: some View {
        Table(of: Row.self, selection: $selection) {
            TableColumn("Name") { row in nameCell(row) }
                .width(min: 240, ideal: 380)
            TableColumn("Kind") { row in
                Text(row.artifact?.kind ?? (row.project.artifacts.count == 1 ? "1 folder" : "\(row.project.artifacts.count) folders"))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140, max: 200)
            TableColumn("Last Activity") { row in
                if row.artifact == nil, let d = row.project.lastActivity {
                    Text(d, format: .relative(presentation: .named))
                        .foregroundStyle(d.daysAgo < state.settings.purgeRecentDays ? .green : .secondary)
                }
            }
            .width(min: 90, ideal: 120, max: 160)
            TableColumn("Size") { row in
                SizeText(bytes: row.artifact?.size ?? row.project.size)
                    .fontWeight(row.artifact == nil ? .semibold : .regular)
            }
            .width(min: 70, ideal: 90, max: 110)
        } rows: {
            ForEach(model.projects) { project in
                DisclosureTableRow(Row(id: project.id, project: project, artifact: nil), isExpanded: Binding(
                    get: { expanded.contains(project.id) },
                    set: { if $0 { expanded.insert(project.id) } else { expanded.remove(project.id) } })) {
                    ForEach(project.artifacts) { a in TableRow(Row(id: a.id, project: project, artifact: a)) }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty { FileContextMenu(paths: Array(ids)) }
        } primaryAction: { ids in SystemAccess.revealInFinder(Array(ids)) }
    }

    @ViewBuilder private func nameCell(_ row: Row) -> some View {
        if let a = row.artifact {
            Toggle(isOn: Binding(get: { !model.excluded.contains(a.path) }, set: { on in
                if on { model.excluded.remove(a.path) } else { model.excluded.insert(a.path) }
            })) {
                HStack(spacing: 6) {
                    FileIcon(path: a.path)
                    Text(String(a.path.dropFirst(row.project.path.count + 1))).font(.body.monospaced())
                }
            }
        } else {
            Toggle(sources: row.project.artifacts.map { a in
                Binding(get: { !model.excluded.contains(a.path) }, set: { on in
                    if on { model.excluded.remove(a.path) } else { model.excluded.insert(a.path) }
                })
            }, isOn: \.self) {
                HStack(spacing: 6) {
                    FileIcon(path: row.project.path)
                    Text(row.project.name).fontWeight(.medium)
                    if let location = relativeLocation(row.project) {
                        Text(location).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }

    /// Where a project sits below its search folder, e.g. "clients/acme", or nil when it's at the top.
    private func relativeLocation(_ project: ProjectArtifacts) -> String? {
        let parent = (project.path as NSString).deletingLastPathComponent
        guard let root = model.existingRoots.first(where: { parent == $0 || parent.hasPrefix($0 + "/") }) else {
            return Paths.abbreviate(parent)
        }
        return parent == root ? nil : String(parent.dropFirst(root.count + 1))
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
        model.scan()
    }
}
