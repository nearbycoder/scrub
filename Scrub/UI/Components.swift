import SwiftUI
import Charts

// MARK: - Storage bar

/// A segmented capacity bar in the style of System Settings › General › Storage.
struct StorageBar: View {
    struct Segment: Identifiable {
        let id: String
        let label: String
        let bytes: Int64
        let color: Color
    }

    let segments: [Segment]
    let total: Int64
    var height: CGFloat = 14
    var showsLegend = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(segments.filter { $0.bytes > 0 }) { seg in
                        Rectangle()
                            .fill(seg.color.gradient)
                            .frame(width: max(2, geo.size.width * CGFloat(seg.bytes) / CGFloat(max(total, 1))))
                            .help("\(seg.label): \(seg.bytes.formattedBytes)")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .clipShape(.rect(cornerRadius: height / 3.5))
            }
            .frame(height: height)
            .animation(.smooth(duration: 0.5), value: segments.map(\.bytes))

            if showsLegend {
                HStack(spacing: 14) {
                    ForEach(segments.filter { $0.bytes > 0 }) { seg in
                        HStack(spacing: 5) {
                            Circle().fill(seg.color).frame(width: 8, height: 8)
                            Text(seg.label).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - Floating action bar

/// The floating control at the bottom of a page. It sits on the control layer, so it uses Liquid Glass;
/// the content underneath stays plain.
struct ActionBar<Summary: View, Actions: View>: View {
    @ViewBuilder var summary: Summary
    @ViewBuilder var actions: Actions

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 18) {
                summary
                    .padding(.leading, 6)
                actions
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }
}

struct SelectionSummary: View {
    let bytes: Int64
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(bytes.formattedBytes)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110, alignment: .leading)
        .animation(.snappy, value: bytes)
    }
}

// MARK: - States

/// Progress placeholder used while a scan runs.
struct ScanningPlaceholder: View {
    let title: String
    let symbol: String
    var detail: String = ""
    var fraction: Double? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
                .symbolEffect(.pulse, options: .repeating)
        } description: {
            VStack(spacing: 12) {
                if let fraction {
                    ProgressView(value: fraction).frame(width: 220)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(detail.isEmpty ? " " : detail)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } actions: {
            if let onCancel { Button("Cancel", action: onCancel) }
        }
    }
}

// MARK: - Charts

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        let top = max(maxValue ?? values.max() ?? 1, 0.0001)
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(color.opacity(0.18))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(SystemMonitor.historyLength - 1, values.count - 1))
        .chartYScale(domain: 0...top)
        .accessibilityHidden(true)
    }
}

// MARK: - Files

/// Finder icons are expensive to fetch; cache them by path.
enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 2000
        return c
    }()

    static func icon(for path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: IconCache.icon(for: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct SizeText: View {
    let bytes: Int64
    var body: some View {
        Text(bytes.formattedBytes)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Standard right-click actions for files shown anywhere in the app.
struct FileContextMenu: View {
    let paths: [String]

    init(path: String) { paths = [path] }
    init(paths: [String]) { self.paths = paths }

    var body: some View {
        Button("Show in Finder") { SystemAccess.revealInFinder(paths) }
        Button(paths.count == 1 ? "Copy Path" : "Copy Paths") { SystemAccess.copyToPasteboard(paths.joined(separator: "\n")) }
        Divider()
        Button("Protect from Cleaning") {
            let settings = AppSettings.shared
            for path in paths.map(Paths.abbreviate) where !settings.protectedPaths.contains(path) {
                settings.protectedPaths.append(path)
            }
        }
    }
}

/// A callout row used for notices inside pages, like missing permissions.
struct NoticeRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(12)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.18)))
    }
}

extension NoticeRow where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: String, message: String) {
        self.init(symbol: symbol, tint: tint, title: title, message: message) { EmptyView() }
    }
}

struct FullDiskAccessNotice: View {
    var message = "Safari, Mail and other apps' data are skipped until you allow access."
    var body: some View {
        NoticeRow(symbol: "lock.shield", tint: .orange, title: "Full Disk Access is off", message: message) {
            Button("Open Settings…") { SystemAccess.openFullDiskAccessSettings() }
        }
    }
}
