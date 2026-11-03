import SwiftUI

struct InstallersView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    @State private var sortOrder = [KeyPathComparator(\InstallerFile.size, order: .reverse)]
    @State private var selection = Set<String>()

    private var model: InstallersModel { state.installers }

    var body: some View {
        content
            .navigationTitle("Installers")
            .navigationSubtitle(model.files.isEmpty ? "" : "\(model.files.count) files · \(model.totalSize.formattedBytes)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.isScanning)
                }
            }
            .onAppear { if model.files.isEmpty && !model.isScanning && model.lastFreed == nil { model.scan() } }
            .confirmationDialog("Move \(model.selected.count) installers to the Trash?", isPresented: $confirm) {
                Button("Move to Trash", role: .destructive) { model.removeSelected() }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isScanning {
            ScanningPlaceholder(title: "Looking for Installers", symbol: "shippingbox")
        } else if model.files.isEmpty {
            ContentUnavailableView {
                Label(model.lastFreed == nil ? "No Installers Found" : "Moved to Trash", systemImage: "shippingbox")
            } description: {
                Text(model.lastFreed.map { "\($0.formattedBytes) of installers moved to the Trash." }
                     ?? "Scrub looks for disk images, packages and installer archives in Downloads, Desktop, Documents, iCloud Drive, Mail and the Homebrew cache.")
            } actions: {
                Button("Scan Again") { model.scan() }
            }
        } else {
            Table(model.files.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { file in
                    Toggle(isOn: Binding(get: { !model.excluded.contains(file.path) }, set: { on in
                        if on { model.excluded.remove(file.path) } else { model.excluded.insert(file.path) }
                    })) {
                        HStack(spacing: 6) {
                            FileIcon(path: file.path)
                            Text(file.name).lineLimit(1)
                        }
                    }
                }
                .width(min: 220, ideal: 360)
                TableColumn("Location", value: \.source) { file in Text(file.source).foregroundStyle(.secondary) }
                    .width(min: 80, ideal: 110, max: 160)
                TableColumn("Date Modified", value: \.modified) { file in
                    Text(file.modified, format: .dateTime.year().month().day()).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 110, max: 140)
                TableColumn("Size", value: \.size) { file in SizeText(bytes: file.size) }
                    .width(min: 70, ideal: 90, max: 110)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty { FileContextMenu(paths: Array(ids)) }
            } primaryAction: { ids in SystemAccess.revealInFinder(Array(ids)) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActionBar {
                    SelectionSummary(bytes: model.selectedSize, detail: "\(model.selected.count) of \(model.files.count) selected")
                } actions: {
                    Button { confirm = true } label: { Text("Move to Trash").padding(.horizontal, 6) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(model.selected.isEmpty || model.isRemoving)
                }
            }
        }
    }
}
