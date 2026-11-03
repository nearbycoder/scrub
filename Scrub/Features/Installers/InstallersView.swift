import SwiftUI

struct InstallersView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    private var model: InstallersModel { state.installers }

    var body: some View {
        Page(spacing: 16) {
            SectionHeader(section: .installers) {
                Button { model.scan() } label: { Label(model.files.isEmpty ? "Scan" : "Rescan", systemImage: "magnifyingglass") }
                    .buttonStyle(.glass)
                    .disabled(model.isScanning)
            }
            if let freed = model.lastFreed {
                ResultBanner(title: "Moved \(freed.formattedBytes) to the Trash", message: "Empty the Trash to reclaim the space.",
                             colors: AppSection.installers.colors) { model.lastFreed = nil }
            }
            if model.isScanning {
                HStack { Spacer(); ScanningOrb(colors: AppSection.installers.colors, size: 150); Spacer() }.padding(.vertical, 30)
            } else if model.files.isEmpty {
                GlassCard {
                    EmptyState(symbol: "opticaldisc.fill", title: "No installers yet",
                               message: "Scrub looks for .dmg, .pkg, .iso, .xip and installer .zip files in Downloads, Desktop, Documents, iCloud Drive, Mail, Telegram and the Homebrew cache.",
                               colors: AppSection.installers.colors)
                }
            } else {
                list
            }
        }
        .onAppear { if model.files.isEmpty && !model.isScanning { model.scan() } }
        .safeAreaInset(edge: .bottom) {
            if !model.files.isEmpty {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.selectedSize.formattedBytes).font(.title3.bold().monospacedDigit()).contentTransition(.numericText())
                        Text("\(model.selected.count) of \(model.files.count) selected").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { confirm = true } label: {
                        Label("Move to Trash", systemImage: "trash.fill").font(.headline).padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppSection.installers.tint)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(model.selected.isEmpty || model.isRemoving)
                }
                .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 18)
            }
        }
        .confirmationDialog("Move \(model.selected.count) installers to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { model.removeSelected() }
        }
    }

    private var list: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("\(model.files.count) installers · \(model.totalSize.formattedBytes)").font(.headline)
                    Spacer()
                    Text("Files newer than \(state.settings.installerAgeDays) days start unselected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                ForEach(model.files) { file in
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(get: { !model.excluded.contains(file.path) }, set: { on in
                            if on { model.excluded.remove(file.path) } else { model.excluded.insert(file.path) }
                        }))
                        .toggleStyle(.checkbox).labelsHidden()
                        FileIcon(path: file.path, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(Paths.abbreviate((file.path as NSString).deletingLastPathComponent))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Pill(text: file.source, color: .teal)
                        Text(file.modified.relativeDescription).font(.caption).foregroundStyle(.tertiary).frame(width: 110, alignment: .trailing)
                        Text(file.size.formattedBytes).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contextMenu { FileContextMenu(path: file.path) }
                }
            }
        }
    }
}
