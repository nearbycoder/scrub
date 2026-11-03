import SwiftUI

struct AnalyzeView: View {
    @Environment(AppState.self) private var state
    @State private var mode: Mode = .map
    @State private var hovered: DiskNode?
    @State private var listSelection: DiskNode.ID?
    @State private var pendingTrash: DiskNode?
    @State private var pendingFileTrash: LargeFile?
    @State private var fileSort = [KeyPathComparator(\LargeFile.size, order: .reverse)]

    enum Mode: String, CaseIterable, Identifiable { case map = "Map", largest = "Largest Files"; var id: Self { self } }

    private var model: AnalyzeModel { state.analyze }

    var body: some View {
        Group {
            if model.isScanning && model.root == nil {
                ScanningPlaceholder(title: "Mapping \(model.scope?.title ?? "Disk")", symbol: "square.grid.3x3.topleft.filled",
                                    detail: "\(model.scannedFiles.formatted()) files · \(model.scannedBytes.formattedBytes)") {
                    model.cancel()
                }
            } else if let current = model.current {
                switch mode {
                case .map: explorer(current)
                case .largest: largestFiles
                }
            } else {
                scopePicker
            }
        }
        .navigationTitle(model.current?.name ?? "Space Lens")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .confirmationDialog("Move “\(pendingTrash?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
            Button("Move to Trash", role: .destructive) { if let n = pendingTrash { model.trash(n) }; pendingTrash = nil }
        } message: { Text("This frees \(pendingTrash?.size.formattedBytes ?? "") once you empty the Trash.") }
        .confirmationDialog("Move “\(pendingFileTrash?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { pendingFileTrash != nil }, set: { if !$0 { pendingFileTrash = nil } })) {
            Button("Move to Trash", role: .destructive) { if let f = pendingFileTrash { model.trash(f) }; pendingFileTrash = nil }
        }
    }

    private var subtitle: String {
        guard let current = model.current else { return "" }
        return "\(current.size.formattedBytes) · \(current.fileCount.formatted()) files"
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!model.canGoBack)
                Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!model.canGoForward)
            }
            .controlGroupStyle(.navigation)
            .disabled(model.root == nil)
        }
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.root == nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(model.scopes) { scope in
                    Button { model.scan(scope) } label: { Label(scope.title, systemImage: scope.symbol) }
                }
                Divider()
                Button("Choose Folder…") { model.scanCustomFolder() }
            } label: {
                Label(model.scope?.title ?? "Location", systemImage: model.scope?.symbol ?? "internaldrive")
            }
            .help("Choose what to analyze")
            Button {
                if let scope = model.scope { model.scan(scope) }
            } label: { Label("Rescan", systemImage: "arrow.clockwise") }
            .disabled(model.scope == nil || model.isScanning)
        }
    }

    private var scopePicker: some View {
        ContentUnavailableView {
            Label("Space Lens", systemImage: "square.grid.3x3.topleft.filled")
        } description: {
            Text("See what's taking up space, folder by folder. Choose a location to map.")
        } actions: {
            HStack {
                ForEach(model.scopes.prefix(3)) { scope in
                    Button { model.scan(scope) } label: { Label(scope.title, systemImage: scope.symbol) }
                }
                Button("Other…") { model.scanCustomFolder() }
            }
            .fixedSize()
            .controlSize(.large)
        }
    }

    // MARK: Explorer

    private func explorer(_ current: DiskNode) -> some View {
        VStack(spacing: 0) {
            PathBar(node: current, isBusy: model.isRefreshingFolder) { model.show($0) }
            Divider()
            HSplitView {
                TreemapView(node: current, hovered: $hovered, onOpen: { model.open($0) }, menu: nodeMenu)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                childList(current)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            }
        }
    }

    private func childList(_ node: DiskNode) -> some View {
        let children = Array(node.displayChildren.prefix(500))
        return Table(children, selection: $listSelection) {
            TableColumn("Name") { child in
                HStack(spacing: 6) {
                    if child.isSynthetic {
                        Image(systemName: "doc.on.doc").foregroundStyle(.tertiary).frame(width: 16)
                    } else {
                        FileIcon(path: child.path)
                    }
                    Text(child.name).lineLimit(1)
                    if child.needsFullDiskAccess {
                        Image(systemName: "lock").foregroundStyle(.orange).help("Allow Full Disk Access to measure this folder")
                    } else if child.isUnreadable {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).help("Couldn't read this folder")
                    }
                }
                .opacity(hovered === child ? 1 : (hovered == nil ? 1 : 0.75))
            }
            TableColumn("Size") { child in
                SizeText(bytes: child.size)
                    .foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 76, max: 96)
        }
        .contextMenu(forSelectionType: DiskNode.ID.self) { ids in
            if let id = ids.first, let child = children.first(where: { $0.id == id }) { nodeMenu(child) }
        } primaryAction: { ids in
            if let id = ids.first, let child = children.first(where: { $0.id == id }) { model.open(child) }
        }
        .onChange(of: listSelection) { _, id in
            hovered = children.first { $0.id == id }
        }
    }

    @ViewBuilder private func nodeMenu(_ node: DiskNode) -> some View {
        if !node.isSynthetic {
            if node.isDirectory && !node.isUnreadable { Button("Open") { model.open(node) } }
            FileContextMenu(path: node.path)
            Divider()
            Button("Move to Trash…", role: .destructive) { pendingTrash = node }
                .disabled(!PathGuard.isAllowed(node.path))
        }
    }

    // MARK: Largest files

    private var largestFiles: some View {
        Table(model.largeFiles.sorted(using: fileSort), sortOrder: $fileSort) {
            TableColumn("Name", value: \.name) { file in
                HStack(spacing: 6) {
                    FileIcon(path: file.path)
                    Text(file.name).lineLimit(1)
                    if file.isStale {
                        Text("Not modified in a year").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 200, ideal: 320)
            TableColumn("Folder", value: \.folder) { file in
                Text(file.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            TableColumn("Modified", value: \.modified) { file in
                Text(file.modified, format: .dateTime.year().month().day()).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110, max: 140)
            TableColumn("Size", value: \.size) { file in SizeText(bytes: file.size) }
                .width(min: 70, ideal: 90, max: 110)
        }
        .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
            if !ids.isEmpty {
                FileContextMenu(paths: Array(ids))
                Divider()
                if ids.count == 1, let file = model.largeFiles.first(where: { $0.id == ids.first }) {
                    Button("Move to Trash…", role: .destructive) { pendingFileTrash = file }
                }
            }
        } primaryAction: { ids in SystemAccess.revealInFinder(Array(ids)) }
        .overlay {
            if model.largeFiles.isEmpty {
                ContentUnavailableView("No Large Files", systemImage: "doc", description: Text("Nothing here is larger than 100 MB."))
            }
        }
    }
}

/// Finder-style path bar for the folder being shown.
private struct PathBar: View {
    let node: DiskNode
    let isBusy: Bool
    let onSelect: (DiskNode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(node.ancestors) { crumb in
                        Button { onSelect(crumb) } label: {
                            HStack(spacing: 4) {
                                FileIcon(path: crumb.path, size: 14)
                                Text(crumb.name).lineLimit(1)
                            }
                        }
                        .buttonStyle(.accessoryBar)
                        if crumb !== node {
                            Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary).font(.caption)
                        }
                    }
                }
            }
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .font(.callout)
    }
}

// MARK: - Treemap

/// Draws two levels of a folder as a squarified treemap in a single Canvas. Layout is computed once
/// per folder and size, hit-testing reuses it, and hover only redraws a lightweight overlay.
struct TreemapView<Menu: View>: View {
    let node: DiskNode
    @Binding var hovered: DiskNode?
    let onOpen: (DiskNode) -> Void
    @ViewBuilder let menu: (DiskNode) -> Menu

    @State private var layout = TreemapLayout()
    @State private var menuTarget: DiskNode?
    @Environment(\.colorScheme) private var scheme

    static var palette: [Color] { [.blue, .purple, .teal, .orange, .pink, .indigo, .green, .yellow, .cyan, .red, .mint, .brown] }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas(rendersAsynchronously: true) { ctx, canvasSize in
                draw(in: &ctx, size: canvasSize)
            }
            .overlay(alignment: .topLeading) { highlight }
            .onAppear { layout.update(node: node, size: size) }
            .onChange(of: size) { _, s in layout.update(node: node, size: s) }
            .onChange(of: node) { _, n in layout.update(node: n, size: size) }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = layout.hit(p)
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture(count: 1).onEnded { value in
                if let hit = layout.hit(value.location) { onOpen(hit) }
            })
            .contextMenu { if let target = hovered { menu(target) } }
            .overlay(alignment: .bottomLeading) { hoverTag }
        }
        .padding(10)
        .background(.background)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let separator = scheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.9)
        for (index, tile) in layout.tiles.enumerated() {
            let color = Self.palette[index % Self.palette.count]
            let rect = tile.rect.insetBy(dx: 1, dy: 1)
            guard rect.width > 1, rect.height > 1 else { continue }
            let path = Path(roundedRect: rect, cornerRadius: min(5, min(rect.width, rect.height) / 4))
            let base = tile.node.isSynthetic ? Color.gray.opacity(0.35) : color.opacity(scheme == .dark ? 0.62 : 0.72)
            ctx.fill(path, with: .color(base))

            if let nested = layout.nested[tile.node.id] {
                for sub in nested {
                    let r = sub.rect.insetBy(dx: 0.5, dy: 0.5)
                    guard r.width > 2, r.height > 2 else { continue }
                    ctx.fill(Path(roundedRect: r, cornerRadius: min(3, min(r.width, r.height) / 4)),
                             with: .color(.white.opacity(sub.node.isSynthetic ? 0.04 : (sub.node.isDirectory ? 0.12 : 0.2))))
                    ctx.stroke(Path(roundedRect: r, cornerRadius: min(3, min(r.width, r.height) / 4)), with: .color(separator.opacity(0.35)), lineWidth: 0.5)
                }
            }
            ctx.stroke(path, with: .color(separator), lineWidth: 1)

            if rect.width > 70 && rect.height > 34 {
                let title = Text(tile.node.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                let detail = Text(tile.node.size.formattedBytes).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                let labelRect = CGRect(x: rect.minX + 6, y: rect.minY + 4, width: rect.width - 12, height: 14)
                ctx.draw(title, in: labelRect)
                if rect.height > 50 {
                    ctx.draw(detail, in: labelRect.offsetBy(dx: 0, dy: 13))
                }
            }
        }
    }

    @ViewBuilder private var highlight: some View {
        if let hovered, let tile = layout.tiles.first(where: { $0.node === hovered }) {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.white, lineWidth: 2)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .frame(width: max(0, tile.rect.width - 2), height: max(0, tile.rect.height - 2))
                .offset(x: tile.rect.minX + 1, y: tile.rect.minY + 1)
                .allowsHitTesting(false)
        }
    }

    /// Floating label for the hovered tile. A transient overlay control, so it uses glass.
    @ViewBuilder private var hoverTag: some View {
        if let hovered {
            HStack(spacing: 8) {
                Text(hovered.name).fontWeight(.medium).lineLimit(1)
                Text(hovered.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                if node.size > 0 {
                    Text(Double(hovered.size) / Double(node.size), format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .padding(10)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

/// Cached treemap geometry for one folder at one size.
struct TreemapLayout {
    private(set) var tiles: [Treemap.Tile] = []
    private(set) var nested: [ObjectIdentifier: [Treemap.Tile]] = [:]
    private var key: (ObjectIdentifier, CGSize, Int64)?

    mutating func update(node: DiskNode, size: CGSize) {
        if let key, key.0 == node.id, key.1 == size, key.2 == node.size { return }
        key = (node.id, size, node.size)
        let rect = CGRect(origin: .zero, size: size)
        tiles = Treemap.layout(Array(node.displayChildren.prefix(150)), in: rect)
        nested = [:]
        for tile in tiles where tile.node.isDirectory && tile.rect.width > 48 && tile.rect.height > 48 {
            let inner = CGRect(x: tile.rect.minX + 4, y: tile.rect.minY + (tile.rect.height > 50 ? 32 : 20),
                               width: tile.rect.width - 8, height: tile.rect.height - (tile.rect.height > 50 ? 36 : 24))
            guard inner.width > 8, inner.height > 8 else { continue }
            nested[tile.node.id] = Treemap.layout(Array(tile.node.displayChildren.prefix(40)), in: inner)
        }
    }

    func hit(_ point: CGPoint) -> DiskNode? {
        tiles.first { $0.rect.contains(point) }?.node
    }
}
