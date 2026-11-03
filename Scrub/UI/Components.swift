import SwiftUI
import Charts

// MARK: - Backdrop

/// A slow-moving mesh of the section's colors that gives Liquid Glass something to refract.
struct SceneBackground: View {
    let colors: [Color]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 6
            let a = colors[0], b = colors[colors.count > 1 ? 1 : 0]
            let base = scheme == .dark ? Color(white: 0.07) : Color(white: 0.97)
            let strength = scheme == .dark ? 0.55 : 0.35
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.18 * sin(t)), Float(0.5 + 0.15 * cos(t * 0.8))], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    a.opacity(strength), base, b.opacity(strength * 0.7),
                    base, a.opacity(strength * 0.35), base,
                    b.opacity(strength * 0.5), base, a.opacity(strength * 0.6),
                ],
                smoothsColors: true
            )
            .background(base)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: colors.description)
    }
}

// MARK: - Glass containers

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    var tint: Color? = nil
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.12)) }
        if interactive { g = g.interactive() }
        return g
    }
}

struct SectionHeader<Trailing: View>: View {
    let section: AppSection
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            IconBadge(symbol: section.symbol, colors: section.colors, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? section.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle ?? section.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.bottom, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(section: AppSection, title: String? = nil, subtitle: String? = nil) {
        self.init(section: section, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Squircle icon with a gradient fill, like the icons in System Settings.
struct IconBadge: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
                    .blendMode(.plusLighter)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: colors.last!.opacity(0.35), radius: size * 0.18, y: size * 0.08)
    }
}

// MARK: - Gauges & charts

struct RingGauge<Center: View>: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 18
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: colors + [colors[0]], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: colors.last!.opacity(0.4), radius: 8)
            center
        }
        .animation(.spring(duration: 0.9), value: progress)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        let top = maxValue ?? max(values.max() ?? 1, 0.0001)
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(SystemMonitor.historyLength - 1, values.count - 1))
        .chartYScale(domain: 0...top)
    }
}

struct MeterBar: View {
    var fraction: Double
    var colors: [Color]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.6), value: fraction)
    }
}

// MARK: - Scanning

/// An animated orb shown while a scan runs.
struct ScanningOrb: View {
    var colors: [Color]
    var progress: Double? = nil
    var size: CGFloat = 200
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors[0].opacity(0.55), colors[1].opacity(0.0)], center: .center, startRadius: 4, endRadius: size * 0.6))
                .scaleEffect(pulse ? 1.08 : 0.92)
            Circle()
                .strokeBorder(AngularGradient(colors: colors + [colors[0].opacity(0)], center: .center), lineWidth: 6)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .padding(size * 0.12)
            if let progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.22)
                    .animation(.easeOut, value: progress)
            }
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: size * 0.2, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating)
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(colors[1].opacity(0.15)), in: .circle)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Small pieces

struct BigNumber: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Int64 {
    /// Splits a byte count into number and unit for display, e.g. ("12.4", "GB").
    var byteParts: (String, String) {
        let s = formattedBytes
        let parts = s.split(separator: " ", maxSplits: 1)
        return parts.count == 2 ? (String(parts[0]), String(parts[1])) : (s, "")
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: .capsule)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var colors: [Color] = [.teal, .blue]

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 72)
            Text(title).font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Standard right-click actions for a file shown anywhere in the app.
struct FileContextMenu: View {
    let path: String
    var body: some View {
        Button("Reveal in Finder", systemImage: "folder") { SystemAccess.revealInFinder([path]) }
        Button("Copy Path", systemImage: "doc.on.doc") { SystemAccess.copyToPasteboard(path) }
        Divider()
        Button("Always Protect This Item", systemImage: "lock.shield") {
            let settings = AppSettings.shared
            let abbreviated = Paths.abbreviate(path)
            if !settings.protectedPaths.contains(abbreviated) { settings.protectedPaths.append(abbreviated) }
        }
    }
}

struct ResultBanner: View {
    let title: String
    let message: String
    var colors: [Color]
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        GlassCard(tint: colors[0]) {
            HStack(spacing: 14) {
                IconBadge(symbol: "checkmark", colors: colors, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(message).foregroundStyle(.secondary)
                }
                Spacer()
                if let onDismiss {
                    Button("Done", action: onDismiss).buttonStyle(.glass)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
