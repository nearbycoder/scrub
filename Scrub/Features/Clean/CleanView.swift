import SwiftUI

struct CleanView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<String>()
    @State private var confirmPersonal = false

    private var model: CleanModel { state.clean }

    var body: some View {
        content
            .navigationTitle("Smart Clean")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.scan()
                    } label: {
                        Label(model.phase == .idle ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.phase == .scanning || model.phase == .cleaning)
                    .help("Scan again")
                }
            }
            .confirmationDialog("Remove personal items?", isPresented: $confirmPersonal) {
                Button("Move to Trash and Clean", role: .destructive) { model.clean() }
            } message: {
                Text("Your selection includes items from “Review Separately”, such as device backups. They'll be moved to the Trash.")
            }
    }

    private var subtitle: String {
        switch model.phase {
        case .ready: "\(model.totalFound.formattedBytes) found"
        case .finished: "Cleanup complete"
        default: ""
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("Smart Clean", systemImage: "sparkles")
            } description: {
                Text("Find caches, logs, developer files, old installers and leftovers from deleted apps. You'll review everything before anything is removed.")
            } actions: {
                Button("Scan") { model.scan() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        case .scanning:
            ScanningPlaceholder(title: model.currentStep.isEmpty ? "Scanning…" : "\(model.currentStep)…", symbol: "sparkles",
                                detail: "\(model.scannedFiles.formatted()) files · \(model.scannedBytes.formattedBytes)")
        case .finished:
            finished
        case .ready, .cleaning:
            results
        }
    }

    private var finished: some View {
        ContentUnavailableView {
            Label("Freed \(model.lastFreed.formattedBytes)", systemImage: "checkmark.circle")
                .symbolRenderingMode(.multicolor)
        } description: {
            let report = model.lastReport
            Text("Removed \(report?.removed.count ?? 0) items." +
                 ((report?.failures.isEmpty ?? true) ? "" : " \(report!.failures.count) were skipped because they're in use or protected."))
        } actions: {
            Button("Scan Again") { model.scan() }
            Button("Show History") { state.section = .history }
        }
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Divider()
            table
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.totalSelected.formattedBytes)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("selected of \(model.totalFound.formattedBytes)")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.lastScanDate != nil {
                    Text("Checked \(model.scannedFiles.formatted()) files in \(model.scanDuration.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .animation(.snappy, value: model.totalSelected)
            StorageBar(segments: CleanGroup.allCases.map {
                .init(id: $0.rawValue, label: $0.title, bytes: model.selectedSize(of: $0), color: $0.color)
            }, total: max(model.totalFound, 1), height: 10)
            if model.skippedForAccess > 0 && !state.hasFullDiskAccess {
                FullDiskAccessNotice(message: "\(model.skippedForAccess) locations, like Safari and Mail, were skipped.")
            }
        }
    }

    private var table: some View {
        Table(of: CleanRow.self, selection: $selection) {
            TableColumn("Name") { row in nameCell(row) }
                .width(min: 280, ideal: 460)
            TableColumn("Items") { row in
                if case .rule(let id) = row.kind, let r = model.resultByID[id] {
                    Text(r.items.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .width(min: 44, ideal: 56, max: 80)
            TableColumn("Last Modified") { row in
                if case .item(let path, _) = row.kind, let d = model.itemByPath[path]?.modified {
                    Text(d, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 130, max: 180)
            TableColumn("Size") { row in sizeCell(row) }
                .width(min: 70, ideal: 90, max: 120)
        } rows: {
            ForEach(model.rows) { group in
                DisclosureTableRow(group, isExpanded: expansion(group.id)) {
                    ForEach(group.children) { rule in
                        DisclosureTableRow(rule, isExpanded: expansion(rule.id)) {
                            ForEach(rule.children) { item in TableRow(item) }
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let paths = ids.filter { model.itemByPath[$0] != nil }
            if !paths.isEmpty { FileContextMenu(paths: Array(paths)) }
        } primaryAction: { ids in
            let paths = ids.filter { model.itemByPath[$0] != nil }
            if !paths.isEmpty { SystemAccess.revealInFinder(Array(paths)) }
        }
        .disabled(model.phase == .cleaning)
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(get: { model.expanded.contains(id) },
                set: { if $0 { model.expanded.insert(id) } else { model.expanded.remove(id) } })
    }

    @ViewBuilder private func nameCell(_ row: CleanRow) -> some View {
        switch row.kind {
        case .group(let group):
            let rules = model.results(in: group).filter { $0.blockedBy == nil }
            Toggle(sources: rules.map { r in
                Binding(get: { r.isSelected }, set: { model.setSelected(r, $0) })
            }, isOn: \.self) {
                Label {
                    Text(group.title).fontWeight(.semibold)
                } icon: {
                    Image(systemName: group.symbol).foregroundStyle(group.color)
                }
            }
            .help(group.subtitle)
        case .rule(let id):
            if let r = model.resultByID[id] {
                Toggle(isOn: Binding(get: { r.isSelected && r.blockedBy == nil }, set: { model.setSelected(r, $0) })) {
                    HStack(spacing: 6) {
                        Text(r.rule.name)
                        if let blocked = r.blockedBy {
                            Text("— \(blocked)").foregroundStyle(.orange)
                        } else if let note = r.rule.note {
                            Image(systemName: "info.circle").foregroundStyle(.tertiary).help(note)
                        }
                    }
                }
                .disabled(r.blockedBy != nil)
            }
        case .item(let path, let ruleID):
            if let r = model.resultByID[ruleID], let item = model.itemByPath[path] {
                Toggle(isOn: Binding(
                    get: { !r.excluded.contains(path) },
                    set: { if $0 { r.excluded.remove(path) } else { r.excluded.insert(path) } }
                )) {
                    HStack(spacing: 6) {
                        FileIcon(path: path)
                        Text(item.name).lineLimit(1)
                        Text(Paths.abbreviate((path as NSString).deletingLastPathComponent))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .disabled(!r.isActive)
            }
        }
    }

    @ViewBuilder private func sizeCell(_ row: CleanRow) -> some View {
        switch row.kind {
        case .group(let group):
            SizeText(bytes: model.selectedSize(of: group)).fontWeight(.semibold)
        case .rule(let id):
            if let r = model.resultByID[id] {
                SizeText(bytes: r.isActive ? r.selectedSize : r.totalSize)
                    .foregroundStyle(r.isActive ? .primary : .secondary)
            }
        case .item(let path, _):
            if let item = model.itemByPath[path] { SizeText(bytes: item.size).foregroundStyle(.secondary) }
        }
    }

    private var actionBar: some View {
        ActionBar {
            if model.phase == .cleaning {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cleaning \(model.currentStep)…").font(.callout).lineLimit(1)
                    ProgressView(value: model.progress).frame(width: 200)
                }
            } else {
                SelectionSummary(bytes: model.totalSelected, detail: "\(model.selectedItemCount.formatted()) items selected")
            }
        } actions: {
            Button {
                let personal = model.results.contains { $0.isActive && $0.rule.group == .separately }
                if personal { confirmPersonal = true } else { model.clean() }
            } label: {
                Text("Clean").padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(model.totalSelected == 0 || model.phase != .ready)
            .keyboardShortcut(.defaultAction)
        }
    }
}
