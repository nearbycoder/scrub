import SwiftUI

struct CleanView: View {
    @Environment(AppState.self) private var state
    @State private var expanded: Set<String> = []
    @State private var confirmSeparately = false

    private var model: CleanModel { state.clean }

    var body: some View {
        Group {
            switch model.phase {
            case .idle: idle
            case .scanning: progressView(title: "Scanning your Mac…", detail: model.currentStep)
            case .cleaning: progressView(title: "Cleaning…", detail: model.currentStep)
            case .ready, .finished: results
            }
        }
        .animation(.smooth, value: model.phase)
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(AppSection.clean.gradient.opacity(0.25)).frame(width: 220, height: 220).blur(radius: 40)
                IconBadge(symbol: AppSection.clean.symbol, colors: AppSection.clean.colors, size: 120)
            }
            VStack(spacing: 8) {
                Text("Smart Clean").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Find caches, logs, developer junk and leftovers in seconds.\nYou'll review everything before anything is removed.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            Button {
                model.scan()
            } label: {
                Label("Start Scan", systemImage: "sparkles").font(.title3.weight(.semibold)).padding(.horizontal, 24).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(AppSection.clean.tint)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(CleanGroup.allCases.filter { $0 != .separately }) { group in
                        Label(group.title, systemImage: group.symbol)
                            .font(.callout)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular.tint(group.tint.opacity(0.15)), in: .capsule)
                    }
                }
            }
            if !state.hasFullDiskAccess {
                Label("Grant Full Disk Access to include Safari, Mail and sandboxed app caches.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressView(title: String, detail: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ScanningOrb(colors: AppSection.clean.colors, progress: model.progress, size: 220)
            VStack(spacing: 6) {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(detail.isEmpty ? " " : detail).foregroundStyle(.secondary).contentTransition(.opacity)
                Text("\(Int(model.progress * 100))%").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Results

    private var results: some View {
        Page(spacing: 18) {
            SectionHeader(section: .clean) {
                Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glass)
            }
            if model.phase == .finished, let report = model.lastReport {
                ResultBanner(
                    title: "Freed \(report.freedBytes.formattedBytes)",
                    message: "Removed \(report.removed.count) items" + (report.failures.isEmpty ? "." : " · \(report.failures.count) skipped (in use or protected)."),
                    colors: AppSection.clean.colors
                ) { model.scan() }
            }
            summary
            if model.skippedForAccess > 0 && !state.hasFullDiskAccess {
                GlassCard(padding: 14, tint: .orange) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").foregroundStyle(.orange)
                        Text("\(model.skippedForAccess) locations, like Safari, Mail and app containers, need Full Disk Access to be scanned.")
                            .font(.callout)
                        Spacer()
                        Button("Grant Access") { SystemAccess.openFullDiskAccessSettings() }.buttonStyle(.glass)
                    }
                }
            }
            if model.results.isEmpty {
                EmptyState(symbol: "checkmark.seal.fill", title: "Squeaky clean", message: "Scrub didn't find anything worth removing right now.",
                           colors: AppSection.clean.colors)
            }
            ForEach(CleanGroup.allCases) { group in
                let results = model.results(in: group)
                if !results.isEmpty { groupCard(group, results) }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .confirmationDialog("Remove personal items?", isPresented: $confirmSeparately) {
            Button("Move to Trash and Clean", role: .destructive) { model.clean() }
        } message: {
            Text("You selected items from “Review Separately”, such as device backups. They'll be moved to the Trash.")
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            GlassCard {
                HStack(spacing: 18) {
                    RingGauge(progress: model.totalFound > 0 ? Double(model.totalSelected) / Double(model.totalFound) : 0,
                              colors: AppSection.clean.colors, lineWidth: 10) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(AppSection.clean.gradient)
                    }
                    .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected").font(.subheadline).foregroundStyle(.secondary)
                        let parts = model.totalSelected.byteParts
                        BigNumber(value: parts.0, unit: parts.1, size: 34)
                        Text("of \(model.totalFound.formattedBytes) found · \(model.selectedItemCount) items")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(CleanGroup.allCases.filter { model.size(of: $0) > 0 }.prefix(5)) { group in
                        HStack {
                            Circle().fill(group.tint).frame(width: 8, height: 8)
                            Text(group.title).font(.callout)
                            Spacer()
                            Text(model.size(of: group).formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 300)
        }
    }

    private func groupCard(_ group: CleanGroup, _ results: [CleanRuleResult]) -> some View {
        GlassCard(padding: 0, tint: group.tint) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    IconBadge(symbol: group.symbol, colors: [group.tint.opacity(0.75), group.tint], size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title).font(.headline)
                        Text(group.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.selectedSize(of: group).formattedBytes)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Toggle("", isOn: Binding(
                        get: { results.allSatisfy { $0.isSelected || $0.blockedBy != nil } && results.contains { $0.isSelected } },
                        set: { v in results.forEach { model.setSelected($0, v) } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .padding(18)

                ForEach(results) { result in
                    Divider().padding(.leading, 18)
                    ruleRow(result)
                }
            }
        }
    }

    private func ruleRow(_ result: CleanRuleResult) -> some View {
        let isExpanded = expanded.contains(result.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { result.isSelected }, set: { model.setSelected(result, $0) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(result.blockedBy != nil)
                Image(systemName: result.rule.symbol)
                    .frame(width: 22)
                    .foregroundStyle(result.rule.group.tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(result.rule.name).font(.body.weight(.medium))
                        if let blocked = result.blockedBy {
                            Pill(text: blocked, color: .orange, symbol: "app.badge.checkmark")
                        }
                    }
                    if let note = result.rule.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(result.items.count) items").font(.caption).foregroundStyle(.tertiary)
                Text(result.isActive ? result.selectedSize.formattedBytes : result.totalSize.formattedBytes)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(result.isActive ? .primary : .secondary)
                    .frame(minWidth: 80, alignment: .trailing)
                Button {
                    withAnimation(.smooth) {
                        if isExpanded { expanded.remove(result.id) } else { expanded.insert(result.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .onTapGesture(count: 1) {
                withAnimation(.smooth) {
                    if isExpanded { expanded.remove(result.id) } else { expanded.insert(result.id) }
                }
            }

            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(result.items.prefix(300)) { item in
                        itemRow(item, in: result)
                    }
                    if result.items.count > 300 {
                        Text("and \(result.items.count - 300) more…").font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
                .padding(.leading, 52)
                .padding(.trailing, 18)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func itemRow(_ item: CleanItem, in result: CleanRuleResult) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { !result.excluded.contains(item.path) },
                set: { if $0 { result.excluded.remove(item.path) } else { result.excluded.insert(item.path) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            FileIcon(path: item.path, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.callout).lineLimit(1)
                Text(Paths.abbreviate((item.path as NSString).deletingLastPathComponent))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let d = item.modified {
                Text(d.relativeDescription).font(.caption).foregroundStyle(.tertiary)
            }
            Text(item.size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contextMenu { FileContextMenu(path: item.path) }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.totalSelected.formattedBytes).font(.title3.bold().monospacedDigit()).contentTransition(.numericText())
                Text(AppSettings.shared.cacheRemovalMode == .trash ? "will move to Trash" : "will be removed").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                let touchesPersonal = model.results.contains { $0.isActive && $0.rule.group == .separately }
                if touchesPersonal { confirmSeparately = true } else { model.clean() }
            } label: {
                Label("Clean", systemImage: "sparkles").font(.headline).padding(.horizontal, 18).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(AppSection.clean.tint)
            .controlSize(.large)
            .fixedSize()
            .disabled(model.totalSelected == 0 || model.phase != .ready)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 18)
        .opacity(model.phase == .ready ? 1 : 0)
    }
}
