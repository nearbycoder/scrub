import SwiftUI

struct UninstallView: View {
    @Environment(AppState.self) private var state
    @State private var showInspector = true
    @State private var confirm: ConfirmKind?

    enum ConfirmKind: Identifiable { case uninstall, reset; var id: Self { self } }

    private var model: UninstallModel { state.uninstall }

    var body: some View {
        @Bindable var model = model
        Table(model.visibleApps, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { app in
                HStack(spacing: 8) {
                    FileIcon(path: app.path, size: 20)
                    Text(app.name)
                    if app.isAppStore {
                        Image(systemName: "bag").font(.caption).foregroundStyle(.tertiary).help("From the App Store")
                    }
                }
            }
            .width(min: 200, ideal: 280)
            TableColumn("Version", value: \.version) { app in
                Text(app.version).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 90, max: 140)
            TableColumn("Last Opened", value: \.lastUsedSort) { app in
                Group {
                    if let d = app.lastUsed { Text(d, format: .relative(presentation: .named)) } else { Text("Never") }
                }
                .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120, max: 160)
            TableColumn("Size", value: \.sizeSort) { app in
                if let size = app.size { SizeText(bytes: size) } else { ProgressView().controlSize(.mini).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            .width(min: 70, ideal: 90, max: 120)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("Show in Finder") { SystemAccess.revealInFinder(Array(ids)) }
                Divider()
                Button("Reset App Data…") { model.selection = ids; loadSelection(); confirm = .reset }
                Button(ids.count == 1 ? "Uninstall…" : "Uninstall \(ids.count) Apps…", role: .destructive) {
                    model.selection = ids; loadSelection(); confirm = .uninstall
                }
            }
        } primaryAction: { ids in
            SystemAccess.revealInFinder(Array(ids))
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search Apps")
        .navigationTitle("Applications")
        .navigationSubtitle(model.isLoading ? "Loading…" : "\(model.apps.count) apps · \(model.apps.reduce(0) { $0 + ($1.size ?? 0) }.formattedBytes)")
        .inspector(isPresented: $showInspector) {
            AppInspector(confirm: $confirm)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .toolbar {
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .help(showInspector ? "Hide Inspector" : "Show Inspector")
            }
        }
        .onChange(of: model.selection) { loadSelection() }
        .onAppear { if model.apps.isEmpty { model.load() } }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { kind in
            Button(kind == .reset ? "Reset" : "Move to Trash", role: .destructive) {
                model.removeSelected(keepApp: kind == .reset)
            }
        } message: { kind in
            Text(kind == .reset
                 ? "The app stays installed, but its settings, caches and data are moved to the Trash."
                 : "The app and its selected files are moved to the Trash. Running apps are quit first.")
        }
    }

    private var confirmTitle: String {
        let apps = model.selectedApps
        let name = apps.count == 1 ? "“\(apps[0].name)”" : "\(apps.count) apps"
        return confirm == .reset ? "Reset \(name)?" : "Uninstall \(name)?"
    }

    private func loadSelection() {
        for app in model.selectedApps { model.loadLeftovers(for: app) }
    }
}

private struct AppInspector: View {
    @Environment(AppState.self) private var state
    @Binding var confirm: UninstallView.ConfirmKind?

    private var model: UninstallModel { state.uninstall }

    var body: some View {
        let apps = model.selectedApps
        Group {
            if model.isRemoving {
                ScanningPlaceholder(title: "Removing", symbol: "trash", detail: model.removalStatus)
            } else if let result = model.lastResult, apps.isEmpty {
                ContentUnavailableView {
                    Label("Moved to Trash", systemImage: "checkmark.circle")
                } description: {
                    Text("\(result.count) app\(result.count == 1 ? "" : "s") and \(result.bytes.formattedBytes) of files.")
                }
            } else if apps.isEmpty {
                ContentUnavailableView("No App Selected", systemImage: "app.dashed",
                                       description: Text("Select an app to see everything that will be removed with it."))
            } else if apps.count == 1 {
                detail(apps[0])
            } else {
                multi(apps)
            }
        }
    }

    private func detail(_ app: InstalledApp) -> some View {
        let leftovers = model.leftovers[app.path] ?? []
        return VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        FileIcon(path: app.path, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.headline)
                            Text(app.version.isEmpty ? app.bundleID : "Version \(app.version)")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Identifier") { Text(app.bundleID).textSelection(.enabled) }
                    LabeledContent("Location", value: app.location)
                    if let d = app.lastUsed { LabeledContent("Last opened") { Text(d, format: .relative(presentation: .named)) } }
                }
                Section {
                    LeftoverToggle(path: app.path, kind: "Application", size: app.size ?? 0, admin: false, locked: true)
                    ForEach(leftovers) { l in
                        LeftoverToggle(path: l.path, kind: l.kind, size: l.size, admin: l.requiresAdmin, locked: false)
                    }
                } header: {
                    HStack {
                        Text("Files to Remove")
                        if model.loadingLeftovers.contains(app.path) { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    if !state.hasFullDiskAccess {
                        Text("Sandboxed app data is only found with Full Disk Access.").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            footer(total: model.totalSize(of: app), canReset: !leftovers.isEmpty)
        }
    }

    private func multi(_ apps: [InstalledApp]) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("\(apps.count) Apps Selected") {
                    ForEach(apps) { app in
                        LabeledContent {
                            Text(model.totalSize(of: app).formattedBytes).monospacedDigit()
                        } label: {
                            HStack { FileIcon(path: app.path, size: 18); Text(app.name) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            footer(total: model.selectionTotal, canReset: true)
        }
    }

    private func footer(total: Int64, canReset: Bool) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Total").foregroundStyle(.secondary)
                Spacer()
                Text(total.formattedBytes).fontWeight(.semibold).monospacedDigit()
            }
            HStack {
                Button("Reset…") { confirm = .reset }
                    .disabled(!canReset)
                    .help("Remove the app's data but keep the app")
                Spacer()
                Button("Uninstall…") { confirm = .uninstall }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
            }
        }
        .padding(16)
    }
}

private struct LeftoverToggle: View {
    @Environment(AppState.self) private var state
    let path: String
    let kind: String
    let size: Int64
    let admin: Bool
    let locked: Bool

    var body: some View {
        let model = state.uninstall
        Toggle(isOn: Binding(
            get: { locked || !model.excludedLeftovers.contains(path) },
            set: { if $0 { model.excludedLeftovers.remove(path) } else { model.excludedLeftovers.insert(path) } }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(kind)
                    if admin { Image(systemName: "lock").font(.caption2).foregroundStyle(.secondary).help("Needs administrator approval") }
                }
                Text(Paths.abbreviate(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .toggleStyle(InspectorCheckboxStyle(trailing: size > 0 ? size.formattedBytes : "—"))
        .disabled(locked)
        .contextMenu { FileContextMenu(path: path) }
    }
}

/// A checkbox row with a trailing value, the way Finder's Get Info lists items.
struct InspectorCheckboxStyle: ToggleStyle {
    let trailing: String

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: configuration.$isOn).toggleStyle(.checkbox).labelsHidden()
            configuration.label
            Spacer(minLength: 8)
            Text(trailing).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
