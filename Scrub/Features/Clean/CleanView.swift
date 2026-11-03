import SwiftUI

struct CleanView: View {
    @Environment(AppState.self) private var state
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
        case .ready, .cleaning: "\(model.totalFound.formattedBytes) found in \(model.results.count.counted("category", "categories"))"
        case .finished: "Cleanup complete"
        default: ""
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle: CleanIntro { model.scan() }
        case .scanning:
            ScanningPlaceholder(title: model.currentStep.isEmpty ? "Scanning…" : "\(model.currentStep)…", symbol: "sparkles",
                                detail: "\(model.scannedFiles.formatted()) files · \(model.scannedBytes.formattedBytes)")
        case .finished: CleanFinished()
        case .ready, .cleaning: browser
        }
    }

    // MARK: Browser

    private var browser: some View {
        HStack(spacing: 0) {
            CategoryList()
                .frame(width: 320)
                .frame(maxHeight: .infinity)
            Divider()
            Group {
                if let id = model.selectedRuleID, let result = model.resultByID[id] {
                    CategoryDetail(result: result)
                } else {
                    ContentUnavailableView("Select a Category", systemImage: "sidebar.left",
                                           description: Text("Choose a category to see what's in it."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
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

// MARK: - Intro

private struct CleanIntro: View {
    let onScan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tint)
                        .frame(width: 88, height: 88)
                        .background(.tint.opacity(0.12), in: .circle)
                    Text("Smart Clean").font(.largeTitle.weight(.semibold))
                    Text("Find caches, logs, developer files, old installers and leftovers from deleted apps.\nYou'll review every item before anything is removed.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button(action: onScan) {
                        Text("Scan").frame(minWidth: 120)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
                }

                // What gets checked, as one grouped list like a System Settings pane.
                let groups = CleanGroup.allCases.filter { $0 != .separately }
                VStack(spacing: 0) {
                    ForEach(groups.indices, id: \.self) { index in
                        let group = groups[index]
                        HStack(spacing: 12) {
                            SymbolTile(symbol: group.symbol, color: group.color, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.title).fontWeight(.medium)
                                Text(group.subtitle).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        if index < groups.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
                .background(.background.secondary, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                .frame(maxWidth: 560)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Finished

private struct CleanFinished: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.clean
        let report = model.lastReport
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.bounce, value: model.lastFreed)
            VStack(spacing: 6) {
                Text("Freed \(model.lastFreed.formattedBytes)").font(.largeTitle.weight(.semibold))
                Text("Removed \((report?.removed.count ?? 0).formatted()) items" +
                     ((report?.failures.isEmpty ?? true) ? "." : ". \(report!.failures.count) were skipped because they're in use or protected."))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Show in History") { state.section = .history }
                Button("Scan Again") { model.scan() }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Category list

private struct CategoryList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.clean
        VStack(spacing: 0) {
            summary
            Divider()
            List(selection: Binding(get: { model.selectedRuleID }, set: { model.selectedRuleID = $0 })) {
                ForEach(CleanGroup.allCases) { group in
                    let results = model.results(in: group)
                    if !results.isEmpty {
                        Section {
                            ForEach(results) { CategoryRow(result: $0).tag(Optional($0.id)) }
                        } header: {
                            GroupHeader(group: group, results: results)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(.background)
    }

    private var summary: some View {
        let model = state.clean
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.totalSelected.formattedBytes)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("selected").foregroundStyle(.secondary)
                Spacer()
            }
            .animation(.snappy, value: model.totalSelected)
            StorageBar(segments: CleanGroup.allCases.map {
                .init(id: $0.rawValue, label: $0.title, bytes: model.selectedSize(of: $0), color: $0.color)
            }, total: max(model.totalFound, 1), height: 8, showsLegend: false)
            HStack {
                Text("of \(model.totalFound.formattedBytes) found")
                Spacer()
                Text("\(model.scannedFiles.formatted()) files in \(model.scanDuration.formatted(.number.precision(.fractionLength(1)))) s")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            if model.skippedForAccess > 0 && !state.hasFullDiskAccess {
                Button {
                    SystemAccess.openFullDiskAccessSettings()
                } label: {
                    Label("Allow Full Disk Access to scan Safari, Mail and app data", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }
}

private struct GroupHeader: View {
    @Environment(AppState.self) private var state
    let group: CleanGroup
    let results: [CleanRuleResult]

    var body: some View {
        let model = state.clean
        let selectable = results.filter { $0.blockedBy == nil }
        HStack {
            Toggle(sources: selectable.map { r in
                Binding(get: { r.isSelected }, set: { model.setSelected(r, $0) })
            }, isOn: \.self) {
                Text(group.title)
            }
            .toggleStyle(.checkbox)
            .disabled(selectable.isEmpty)
            Spacer()
            Text(model.selectedSize(of: group).formattedBytes)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct CategoryRow: View {
    @Environment(AppState.self) private var state
    let result: CleanRuleResult

    var body: some View {
        let model = state.clean
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { result.isActive }, set: { model.setSelected(result, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(result.blockedBy != nil)
            RuleIcon(rule: result.rule, size: 28)
                .saturation(result.blockedBy == nil ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.rule.name).lineLimit(1).help(result.rule.name)
                Group {
                    if let blocked = result.blockedBy {
                        Text(blocked).foregroundStyle(.orange)
                    } else {
                        Text("\(result.items.count.formatted()) item\(result.items.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 6)
            Text((result.isActive ? result.selectedSize : result.totalSize).formattedBytes)
                .monospacedDigit()
                .foregroundStyle(result.isActive ? .primary : .secondary)
        }
        .padding(.vertical, 3)
        .opacity(result.blockedBy == nil ? 1 : 0.7)
    }
}

// MARK: - Detail

private struct CategoryDetail: View {
    @Environment(AppState.self) private var state
    let result: CleanRuleResult
    @State private var sortOrder = [KeyPathComparator(\CleanItem.size, order: .reverse)]
    @State private var selection = Set<String>()

    var body: some View {
        let model = state.clean
        let rule = result.rule
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    RuleIcon(rule: rule, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name).font(.title2.weight(.semibold))
                        Text(rule.group.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text((result.isActive ? result.selectedSize : result.totalSize).formattedBytes)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("\(result.selectedItems.count) of \(result.items.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(rule.about)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Toggle("Include", isOn: Binding(get: { result.isActive }, set: { model.setSelected(result, $0) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(result.blockedBy != nil)
                        .fixedSize()
                    Label(rule.safety.title, systemImage: rule.safety.symbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(rule.safety.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(rule.safety.color.opacity(0.12), in: .capsule)
                    if result.blockedBy != nil {
                        if let id = rule.bundleIDs.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
                            Button("Quit and Rescan") {
                                NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
                                Task { try? await Task.sleep(for: .seconds(2)); model.scan() }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
            }
            .padding(20)

            Divider()

            Table(result.items.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { item in
                    Toggle(isOn: Binding(
                        get: { !result.excluded.contains(item.path) },
                        set: { if $0 { result.excluded.remove(item.path) } else { result.excluded.insert(item.path) } }
                    )) {
                        ItemLabel(item: item)
                    }
                    .disabled(!result.isActive)
                }
                .width(min: 180, ideal: 300)
                TableColumn("Last Modified", value: \.modifiedSort) { item in
                    if let d = item.modified { Text(d, format: .relative(presentation: .named)).foregroundStyle(.secondary) }
                }
                .width(min: 90, ideal: 120, max: 160)
                TableColumn("Size", value: \.size) { item in
                    SizeText(bytes: item.size).foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 85, max: 110)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty { FileContextMenu(paths: Array(ids)) }
            } primaryAction: { ids in SystemAccess.revealInFinder(Array(ids)) }
        }
        .disabled(model.phase == .cleaning)
        .id(result.id)
    }
}

/// A file or folder in a category. Folders named after an installed app's bundle identifier show
/// that app's name and icon, so `com.surfshark.vpnclient.macos.direct` reads as Surfshark.
private struct ItemLabel: View {
    let item: CleanItem

    var body: some View {
        HStack(spacing: 6) {
            if let app = OwningApp.lookup(item.name) {
                FileIcon(path: app.path)
                Text(app.name).lineLimit(1)
                Text(item.name).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            } else {
                FileIcon(path: item.path)
                Text(item.name).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

enum OwningApp {
    private static var cache: [String: (name: String, path: String)?] = [:]

    static func lookup(_ fileName: String) -> (name: String, path: String)? {
        if let hit = cache[fileName] { return hit }
        var id = fileName
        for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) { id = String(id.dropLast(suffix.count)) }
        var result: (name: String, path: String)?
        if OrphanFinder.isBundleIdentifier(id), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            result = (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url.path)
        }
        cache[fileName] = result
        return result
    }
}
