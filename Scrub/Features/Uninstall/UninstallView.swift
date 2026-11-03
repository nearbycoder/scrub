import SwiftUI

struct UninstallView: View {
    @Environment(AppState.self) private var state
    @State private var confirm: ConfirmKind?

    enum ConfirmKind: Identifiable { case uninstall, reset; var id: Self { self } }

    private var model: UninstallModel { state.uninstall }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(section: .uninstall) {
                Picker("Sort", selection: $model.sort) {
                    ForEach(UninstallModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .labelsHidden()
            }
            if let result = model.lastResult {
                ResultBanner(title: "Removed \(result.count) app\(result.count == 1 ? "" : "s")",
                             message: "\(result.bytes.formattedBytes) moved to the Trash.",
                             colors: AppSection.uninstall.colors) { model.lastResult = nil }
            }
            HStack(alignment: .top, spacing: 18) {
                appList
                    .frame(width: 400)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .onAppear { if model.apps.isEmpty { model.load() } }
        .confirmationDialog(confirm == .reset ? "Reset app data?" : "Uninstall \(model.selectedApps.count == 1 ? model.selectedApps[0].name : "\(model.selectedApps.count) apps")?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { kind in
            Button(kind == .reset ? "Reset" : "Move to Trash", role: .destructive) {
                model.removeSelected(keepApp: kind == .reset)
            }
        } message: { kind in
            Text(kind == .reset
                 ? "The app stays installed but its settings, caches and data are moved to the Trash, like a fresh install."
                 : "The app and the selected leftovers are moved to the Trash. Running apps are quit first.")
        }
    }

    // MARK: List

    private var appList: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(model.apps.count) apps", text: $model.search)
                    .textFieldStyle(.plain)
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .glassEffect(.regular, in: .capsule)
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.visibleApps) { app in
                        appRow(app)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let selected = model.selection.contains(app.path)
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { selected }, set: { on in
                if on { model.selection.insert(app.path); model.loadLeftovers(for: app) } else { model.selection.remove(app.path) }
            }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            FileIcon(path: app.path, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                Text(app.lastUsed.map { "Used \($0.relativeDescription)" } ?? "Never opened")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let size = model.sizes[app.path] {
                Text(size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? AppSection.uninstall.tint.opacity(0.16) : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .onTapGesture {
            // Plain click focuses one app; ⌘-click adds to the selection.
            if NSEvent.modifierFlags.contains(.command) {
                if selected { model.selection.remove(app.path) } else { model.selection.insert(app.path) }
            } else {
                model.selection = [app.path]
            }
            model.loadLeftovers(for: app)
        }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") { SystemAccess.revealInFinder([app.path]) }
            Button("Reset App Data…", systemImage: "arrow.counterclockwise") {
                model.selection = [app.path]; model.loadLeftovers(for: app); confirm = .reset
            }
            Button("Uninstall…", systemImage: "trash", role: .destructive) {
                model.selection = [app.path]; model.loadLeftovers(for: app); confirm = .uninstall
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        let apps = model.selectedApps
        if model.isRemoving {
            GlassCard {
                VStack(spacing: 16) {
                    ScanningOrb(colors: AppSection.uninstall.colors, size: 140)
                    Text(model.removalStatus).font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if apps.isEmpty {
            GlassCard {
                EmptyState(symbol: "xmark.app.fill", title: "Choose an app",
                           message: "Scrub finds the preferences, caches, containers and launch agents each app leaves behind. ⌘-click to select several.",
                           colors: AppSection.uninstall.colors)
                    .frame(maxWidth: .infinity, minHeight: 360)
            }
        } else if apps.count == 1 {
            singleDetail(apps[0])
        } else {
            multiDetail(apps)
        }
    }

    private func singleDetail(_ app: InstalledApp) -> some View {
        let leftovers = model.leftovers[app.path] ?? []
        return GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    FileIcon(path: app.path, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("\(app.version.isEmpty ? "" : "Version \(app.version) · ")\(app.bundleID)")
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack(spacing: 6) {
                            Pill(text: app.location, symbol: "folder")
                            if app.isAppStore { Pill(text: "App Store", color: .blue, symbol: "bag.fill") }
                            if app.isRunning { Pill(text: "Running", color: .green, symbol: "play.fill") }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        let parts = model.totalSize(of: app).byteParts
                        BigNumber(value: parts.0, unit: parts.1, size: 32)
                        Text("total to remove").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(22)

                Divider()
                HStack {
                    Text("Leftovers").font(.headline)
                    if model.loadingLeftovers.contains(app.path) { ProgressView().controlSize(.small) }
                    Spacer()
                    Text("\(leftovers.count) found").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        leftoverRow(path: app.path, kind: "Application", size: model.sizes[app.path] ?? 0, admin: false, locked: true)
                        ForEach(leftovers) { l in
                            leftoverRow(path: l.path, kind: l.kind, size: l.size, admin: l.requiresAdmin, locked: false)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(maxHeight: .infinity)

                Divider()
                HStack {
                    Button("Reset App Data…") { confirm = .reset }
                        .buttonStyle(.glass)
                        .disabled(leftovers.isEmpty)
                    Spacer()
                    Button {
                        confirm = .uninstall
                    } label: {
                        Label("Uninstall", systemImage: "trash.fill").padding(.horizontal, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppSection.uninstall.tint)
                    .controlSize(.large)
                }
                .padding(16)
            }
        }
    }

    private func leftoverRow(path: String, kind: String, size: Int64, admin: Bool, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { locked || !model.excludedLeftovers.contains(path) },
                set: { if $0 { model.excludedLeftovers.remove(path) } else { model.excludedLeftovers.insert(path) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(locked)
            FileIcon(path: path, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind).font(.callout.weight(.medium))
                Text(Paths.abbreviate(path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if admin { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.orange).help("Requires administrator approval") }
            Text(size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contextMenu { FileContextMenu(path: path) }
    }

    private func multiDetail(_ apps: [InstalledApp]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: -14) {
                    ForEach(apps.prefix(8)) { FileIcon(path: $0.path, size: 64) }
                }
                Text("\(apps.count) apps selected").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(apps.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(3)
                HStack(alignment: .firstTextBaseline) {
                    let parts = model.selectionTotal.byteParts
                    BigNumber(value: parts.0, unit: parts.1, size: 36)
                    Text("including leftovers").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Clear Selection") { model.selection = [] }.buttonStyle(.glass)
                    Spacer()
                    Button { confirm = .uninstall } label: {
                        Label("Uninstall \(apps.count) Apps", systemImage: "trash.fill").padding(.horizontal, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppSection.uninstall.tint)
                    .controlSize(.large)
                }
            }
        }
    }
}
