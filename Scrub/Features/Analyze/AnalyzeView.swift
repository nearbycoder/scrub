import SwiftUI

struct AnalyzeView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = .map
    @State private var pendingTrash: DiskNode?
    @State private var pendingFileTrash: LargeFile?

    enum Tab: String, CaseIterable, Identifiable { case map = "Map", largest = "Largest Files"; var id: Self { self } }

    static let palette: [Color] = [
        Color(red: 0.40, green: 0.47, blue: 1.00), Color(red: 0.20, green: 0.75, blue: 0.95), Color(red: 0.62, green: 0.40, blue: 0.98),
        Color(red: 0.18, green: 0.80, blue: 0.68), Color(red: 1.00, green: 0.55, blue: 0.40), Color(red: 0.95, green: 0.40, blue: 0.70),
        Color(red: 1.00, green: 0.75, blue: 0.30), Color(red: 0.45, green: 0.80, blue: 0.40), Color(red: 0.30, green: 0.60, blue: 0.85),
        Color(red: 0.80, green: 0.50, blue: 0.95),
    ]

    private var model: AnalyzeModel { state.analyze }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(section: .analyze) { headerControls }
            if model.isScanning && model.root == nil {
                scanning
            } else if let current = model.current {
                explorer(current)
            } else {
                scopePicker
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .confirmationDialog("Move “\(pendingTrash?.name ?? "")” to the Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
            Button("Move to Trash", role: .destructive) { if let n = pendingTrash { model.trash(n) }; pendingTrash = nil }
        } message: { Text("\(pendingTrash?.size.formattedBytes ?? "") will be freed once you empty the Trash.") }
        .confirmationDialog("Move “\(pendingFileTrash?.name ?? "")” to the Trash?", isPresented: Binding(get: { pendingFileTrash != nil }, set: { if !$0 { pendingFileTrash = nil } })) {
            Button("Move to Trash", role: .destructive) { if let f = pendingFileTrash { model.trash(f) }; pendingFileTrash = nil }
        }
    }

    private var headerControls: some View {
        HStack {
            if model.root != nil {
                Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            Menu {
                ForEach(model.scopes) { scope in
                    Button(scope.title, systemImage: scope.symbol) { model.scan(scope) }
                }
                Divider()
                Button("Choose Folder…", systemImage: "folder.badge.plus") { model.scanCustomFolder() }
            } label: {
                Label(model.scope?.title ?? "Choose Location", systemImage: model.scope?.symbol ?? "internaldrive")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            if let scope = model.scope, !model.isScanning {
                Button { model.scan(scope) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.glass)
                    .help("Rescan")
            }
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What would you like to explore?").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(model.scopes) { scope in
                    Button { model.scan(scope) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            IconBadge(symbol: scope.symbol, colors: AppSection.analyze.colors, size: 46)
                            Text(scope.title).font(.headline).foregroundStyle(.primary)
                            Text(Paths.abbreviate(scope.path)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .contentShape(.rect(cornerRadius: 22))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                }
                Button { model.scanCustomFolder() } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        IconBadge(symbol: "folder.badge.plus", colors: [.gray, .secondary], size: 46)
                        Text("Choose Folder…").font(.headline).foregroundStyle(.primary)
                        Text("Any folder or drive").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .contentShape(.rect(cornerRadius: 22))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var scanning: some View {
        VStack(spacing: 22) {
            Spacer()
            ScanningOrb(colors: AppSection.analyze.colors, size: 200)
            Text("Mapping \(model.scope?.title ?? "disk")…").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("\(model.scannedFiles.formatted()) items · \(model.scannedBytes.formattedBytes)")
                .font(.headline.monospacedDigit()).foregroundStyle(.secondary).contentTransition(.numericText())
            Button("Cancel") { model.cancel() }.buttonStyle(.glass)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Explorer

    private func explorer(_ current: DiskNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            breadcrumbs(current)
            switch tab {
            case .map:
                HStack(alignment: .top, spacing: 16) {
                    treemap(current)
                    childList(current).frame(width: 320)
                }
            case .largest:
                largestFiles
            }
        }
    }

    private func breadcrumbs(_ node: DiskNode) -> some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button { model.goUp() } label: { Image(systemName: "chevron.left").frame(width: 18, height: 18) }
                    .buttonStyle(.glass)
                    .disabled(node.parent == nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(node.ancestors) { crumb in
                            Button { model.current = crumb } label: {
                                Text(crumb.name).lineLimit(1)
                            }
                            .buttonStyle(.glass)
                            .tint(crumb === node ? AppSection.analyze.tint : nil)
                            if crumb !== node { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                        }
                    }
                }
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
                Text("\(node.size.formattedBytes) · \(node.fileCount.formatted()) files")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func treemap(_ node: DiskNode) -> some View {
        let children = Array(node.displayChildren.prefix(80))
        return GeometryReader { geo in
            let tiles = Treemap.layout(children, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.node.id) { index, tile in
                    TreemapTile(node: tile.node, color: Self.palette[index % Self.palette.count],
                                isHovered: model.hovered === tile.node)
                        .frame(width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3))
                        .offset(x: tile.rect.minX + 1.5, y: tile.rect.minY + 1.5)
                        .onHover { inside in model.hovered = inside ? tile.node : (model.hovered === tile.node ? nil : model.hovered) }
                        .onTapGesture { withAnimation(.smooth) { model.open(tile.node) } }
                        .contextMenu { nodeMenu(tile.node) }
                }
            }
            .animation(.smooth(duration: 0.35), value: node.id)
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay(alignment: .bottomLeading) {
            if let h = model.hovered {
                HStack(spacing: 8) {
                    FileIcon(path: h.isSynthetic ? node.path : h.path, size: 18)
                    Text(h.name).font(.callout.weight(.semibold))
                    Text(h.size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    if node.size > 0 {
                        Text("\(Int(Double(h.size) / Double(node.size) * 100))%").font(.callout).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .padding(14)
                .allowsHitTesting(false)
            }
        }
    }

    private func childList(_ node: DiskNode) -> some View {
        let children = node.displayChildren
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(children.prefix(200).enumerated()), id: \.element.id) { index, child in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(Self.palette[index % Self.palette.count]).frame(width: 6, height: 28)
                        FileIcon(path: child.isSynthetic ? node.path : child.path, size: 22)
                            .opacity(child.isSynthetic ? 0.5 : 1)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(child.name).font(.callout).lineLimit(1)
                                if child.needsFullDiskAccess {
                                    Image(systemName: "lock.fill").foregroundStyle(.orange).help("Grant Full Disk Access to measure this folder")
                                } else if child.isUnreadable {
                                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange).help("Couldn't read this folder")
                                }
                            }
                            MeterBar(fraction: node.size > 0 ? Double(child.size) / Double(node.size) : 0,
                                     colors: [Self.palette[index % Self.palette.count].opacity(0.6), Self.palette[index % Self.palette.count]], height: 4)
                        }
                        Text(child.size.formattedBytes).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(model.hovered === child ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                    .onHover { inside in if inside { model.hovered = child } }
                    .onTapGesture { withAnimation(.smooth) { model.open(child) } }
                    .contextMenu { nodeMenu(child) }
                }
            }
            .padding(8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder private func nodeMenu(_ node: DiskNode) -> some View {
        if !node.isSynthetic {
            if node.isDirectory { Button("Open", systemImage: "arrow.down.right.circle") { model.open(node) } }
            FileContextMenu(path: node.path)
            Divider()
            Button("Move to Trash…", systemImage: "trash", role: .destructive) { pendingTrash = node }
                .disabled(!PathGuard.isAllowed(node.path))
        }
    }

    private var largestFiles: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if model.largeFiles.isEmpty {
                    EmptyState(symbol: "doc.fill", title: "No large files", message: "Nothing over 100 MB in this location.",
                               colors: AppSection.analyze.colors)
                }
                ForEach(model.largeFiles) { file in
                    HStack(spacing: 12) {
                        FileIcon(path: file.path, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(file.name).font(.body.weight(.medium)).lineLimit(1)
                                if file.isUnused { Pill(text: "Unused for a year", color: .orange) }
                            }
                            Text(Paths.abbreviate((file.path as NSString).deletingLastPathComponent))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text("Modified \(file.modified.relativeDescription)").font(.caption).foregroundStyle(.tertiary)
                        Text(file.size.formattedBytes).font(.body.monospacedDigit().weight(.semibold)).frame(width: 90, alignment: .trailing)
                        Button { SystemAccess.revealInFinder([file.path]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.glass).help("Reveal in Finder")
                        Button { pendingFileTrash = file } label: { Image(systemName: "trash") }
                            .buttonStyle(.glass).help("Move to Trash")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contextMenu { FileContextMenu(path: file.path) }
                }
            }
            .padding(8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct TreemapTile: View {
    let node: DiskNode
    let color: Color
    let isHovered: Bool

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: min(12, min(size.width, size.height) / 4), style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(node.isSynthetic ? 0.35 : 0.85), color.opacity(node.isSynthetic ? 0.25 : 0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if node.isDirectory, size.width > 60, size.height > 50 {
                    Canvas { ctx, canvasSize in
                        let inner = CGRect(x: 4, y: 26, width: canvasSize.width - 8, height: canvasSize.height - 30)
                        guard inner.width > 10, inner.height > 10 else { return }
                        for tile in Treemap.layout(Array(node.displayChildren.prefix(40)), in: inner) {
                            let r = tile.rect.insetBy(dx: 1, dy: 1)
                            guard r.width > 2, r.height > 2 else { continue }
                            ctx.fill(Path(roundedRect: r, cornerRadius: min(6, min(r.width, r.height) / 4)),
                                     with: .color(.white.opacity(tile.node.isSynthetic ? 0.06 : 0.16)))
                        }
                    }
                    .allowsHitTesting(false)
                }
                if size.width > 64 && size.height > 30 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                        if size.height > 46 { Text(node.size.formattedBytes).font(.caption2.monospacedDigit()).opacity(0.85) }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(.horizontal, 7)
                    .padding(.top, 5)
                }
                RoundedRectangle(cornerRadius: min(12, min(size.width, size.height) / 4), style: .continuous)
                    .strokeBorder(.white.opacity(isHovered ? 0.9 : 0.18), lineWidth: isHovered ? 2 : 0.5)
            }
        }
        .scaleEffect(isHovered ? 0.99 : 1)
        .animation(.snappy(duration: 0.15), value: isHovered)
        .contentShape(.rect)
    }
}
