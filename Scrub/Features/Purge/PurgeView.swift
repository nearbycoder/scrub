import SwiftUI

struct PurgeView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    @State private var filter: Filter = .all
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Projects", inactive = "Inactive"
        var id: Self { self }
    }

    private var model: PurgeModel { state.purge }

    var body: some View {
        content
            .navigationTitle("Project Purge")
            .navigationSubtitle(subtitle)
            .toolbar {
                if hasResults {
                    ToolbarItem(placement: .principal) {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .help("Inactive projects haven't changed in the last \(state.settings.purgeRecentDays) days")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { addRoot() } label: { Label("Add Folder", systemImage: "folder.badge.plus") }
                        .help("Add a folder to search for projects")
                    Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.isScanning || model.isPurging)
                }
            }
            .modifier(SearchWhen(active: hasResults, text: $search, prompt: "Search Projects"))
            .confirmationDialog("Remove \(model.selectedArtifacts.count.counted("build folder"))?", isPresented: $confirm) {
                Button(state.settings.purgeRemovalMode == .trash ? "Move to Trash" : "Delete \(model.selectedSize.formattedBytes)", role: .destructive) {
                    model.purge()
                }
            } message: {
                Text("They only contain generated files. Install or build the project again to restore them.")
            }
    }

    private var hasResults: Bool { !model.projects.isEmpty && !model.isScanning }

    private var subtitle: String {
        guard !model.projects.isEmpty else { return model.existingRoots.map(Paths.abbreviate).joined(separator: ", ") }
        let folders = model.projects.reduce(0) { $0 + $1.artifacts.count }
        return "\(model.totalSize.formattedBytes) in \(folders.counted("folder")) across \(model.projects.count.counted("project"))"
    }

    private var visibleProjects: [ProjectArtifacts] {
        let cutoff = Date().addingTimeInterval(-Double(state.settings.purgeRecentDays) * 86_400)
        return model.projects.filter { p in
            (filter == .all || (p.lastActivity ?? .distantPast) < cutoff)
                && (search.isEmpty || p.name.localizedCaseInsensitiveContains(search) || p.kind.label.localizedCaseInsensitiveContains(search))
        }
    }

    /// Projects grouped under the folder they were found in, so each card doesn't repeat it.
    private var groups: [(root: String, projects: [ProjectArtifacts])] {
        let roots = model.existingRoots.sorted { $0.count > $1.count }
        let byRoot = Dictionary(grouping: visibleProjects) { p in
            roots.first { p.path.hasPrefix($0 + "/") } ?? (p.path as NSString).deletingLastPathComponent
        }
        return byRoot.map { ($0.key, $0.value) }
            .sorted { $0.projects.reduce(0) { $0 + $1.size } > $1.projects.reduce(0) { $0 + $1.size } }
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
                    Text("Freed \(freed.formattedBytes). There's nothing else to remove.")
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
            let largest = model.projects.map(\.size).max() ?? 1
            List {
                ForEach(groups, id: \.root) { group in
                    Section {
                        ForEach(group.projects) { project in
                            ProjectCard(project: project, largest: largest, root: group.root)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            Text(Paths.abbreviate(group.root))
                            Spacer()
                            Text(group.projects.reduce(0) { $0 + $1.size }.formattedBytes)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                    }
                }
                Color.clear.frame(height: 70).listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 10, for: .scrollContent)
            .overlay {
                if visibleProjects.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
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
        model.scan()
    }
}

/// One project: its stack, how recently it changed, and chips for each removable build folder.
private struct ProjectCard: View {
    @Environment(AppState.self) private var state
    let project: ProjectArtifacts
    let largest: Int64
    let root: String

    var body: some View {
        let model = state.purge
        let selected = project.artifacts.filter { !model.excluded.contains($0.path) }
        let recent = (project.lastActivity ?? .distantPast) > Date().addingTimeInterval(-Double(state.settings.purgeRecentDays) * 86_400)

        HStack(alignment: .top, spacing: 14) {
            Toggle(sources: project.artifacts.map { a in
                Binding(get: { !model.excluded.contains(a.path) }, set: { on in
                    if on { model.excluded.remove(a.path) } else { model.excluded.insert(a.path) }
                })
            }, isOn: \.self) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .padding(.top, 12)

            KindBadge(kind: project.kind)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(project.name).font(.headline)
                    Text(project.kind.label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text((selected.isEmpty ? project.size : selected.reduce(0) { $0 + $1.size }).formattedBytes)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(selected.isEmpty ? .secondary : .primary)
                        .contentTransition(.numericText())
                }
                HStack(spacing: 6) {
                    if let d = project.lastActivity {
                        Image(systemName: recent ? "circle.fill" : "moon.zzz")
                            .font(.system(size: recent ? 6 : 10))
                            .foregroundStyle(recent ? .green : .secondary)
                        Text(recent ? "Active, changed \(d.relativeDescription)" : "Last changed \(d.relativeDescription)")
                    }
                    // Only nested projects need a location; the section header names the folder.
                    let parent = (project.path as NSString).deletingLastPathComponent
                    if parent != root, parent.hasPrefix(root + "/") {
                        Text("·")
                        Text(String(parent.dropFirst(root.count + 1)))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                GeometryReader { geo in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(recent ? Color.secondary.opacity(0.5) : Color.accentColor)
                                .frame(width: max(4, geo.size.width * CGFloat(project.size) / CGFloat(max(largest, 1))))
                        }
                }
                .frame(height: 4)

                FlowLayout(spacing: 6) {
                    ForEach(project.artifacts) { artifact in
                        ArtifactChip(artifact: artifact, project: project)
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected.isEmpty ? Color.clear : Color.accentColor.opacity(0.45), lineWidth: 1)
        }
        .animation(.snappy, value: selected.isEmpty)
        .contextMenu {
            Button("Show in Finder") { SystemAccess.revealInFinder([project.path]) }
            Button("Copy Path") { SystemAccess.copyToPasteboard(project.path) }
            Divider()
            Button("Never Purge This Project") {
                if !state.settings.protectedPaths.contains(Paths.abbreviate(project.path)) {
                    state.settings.protectedPaths.append(Paths.abbreviate(project.path))
                }
                project.artifacts.forEach { model.excluded.insert($0.path) }
            }
        }
    }
}

private struct ArtifactChip: View {
    @Environment(AppState.self) private var state
    let artifact: BuildArtifact
    let project: ProjectArtifacts

    var body: some View {
        let model = state.purge
        let on = !model.excluded.contains(artifact.path)
        let relative = String(artifact.path.dropFirst(project.path.count + 1))
        Button {
            withAnimation(.snappy) {
                if on { model.excluded.insert(artifact.path) } else { model.excluded.remove(artifact.path) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                Text(relative).font(.callout.monospaced())
                Text(artifact.size.formattedBytes).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(on ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: .capsule)
            .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(artifact.kind) · \(Paths.abbreviate(artifact.path))")
        .contextMenu { FileContextMenu(path: artifact.path) }
    }
}

/// A language badge in the style of a file-type icon.
struct KindBadge: View {
    let kind: ProjectKind
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .overlay {
                Text(kind.badge)
                    .font(.system(size: size * (kind.badge.count > 2 ? 0.3 : 0.38), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch kind {
        case .node: Color(red: 0.33, green: 0.62, blue: 0.27)
        case .rust: Color(red: 0.80, green: 0.36, blue: 0.20)
        case .swift: Color(red: 0.95, green: 0.38, blue: 0.24)
        case .xcode: .blue
        case .python: Color(red: 0.22, green: 0.45, blue: 0.70)
        case .gradle: .purple
        case .flutter: .cyan
        case .php: .indigo
        case .ruby: .red
        case .go: .teal
        case .cmake: .gray
        case .other: .secondary
        }
    }
}

/// Adds a toolbar search field only while there's something to search.
struct SearchWhen: ViewModifier {
    let active: Bool
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        if active {
            content.searchable(text: $text, placement: .toolbar, prompt: prompt)
        } else {
            content
        }
    }
}

/// Lays out children left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
