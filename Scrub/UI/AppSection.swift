import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, clean, purge, installers, uninstall, analyze, optimize, status, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .clean: "Smart Clean"
        case .purge: "Project Purge"
        case .installers: "Installers"
        case .uninstall: "Uninstaller"
        case .analyze: "Space Lens"
        case .optimize: "Optimize"
        case .status: "Live Status"
        case .history: "History"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Your Mac at a glance."
        case .clean: "Clear caches, logs and junk your Mac doesn't need."
        case .purge: "Reclaim space from build folders in old projects."
        case .installers: "Remove disk images and packages you already installed."
        case .uninstall: "Remove apps completely, leftovers and all."
        case .analyze: "See exactly what's filling your disk."
        case .optimize: "Run maintenance that keeps macOS fast and tidy."
        case .status: "Live CPU, memory, disk, network and battery."
        case .history: "Everything Scrub has cleaned, and when."
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles.rectangle.stack.fill"
        case .clean: "bubbles.and.sparkles.fill"
        case .purge: "shippingbox.fill"
        case .installers: "opticaldisc.fill"
        case .uninstall: "xmark.app.fill"
        case .analyze: "square.grid.3x3.middle.filled"
        case .optimize: "bolt.heart.fill"
        case .status: "waveform.path.ecg.rectangle.fill"
        case .history: "clock.arrow.circlepath"
        }
    }

    var colors: [Color] {
        switch self {
        case .overview: [Color(red: 0.20, green: 0.78, blue: 0.85), Color(red: 0.39, green: 0.40, blue: 0.96)]
        case .clean: [Color(red: 0.16, green: 0.84, blue: 0.75), Color(red: 0.13, green: 0.55, blue: 0.95)]
        case .purge: [Color(red: 1.00, green: 0.62, blue: 0.24), Color(red: 0.95, green: 0.30, blue: 0.42)]
        case .installers: [Color(red: 0.36, green: 0.86, blue: 0.56), Color(red: 0.10, green: 0.62, blue: 0.62)]
        case .uninstall: [Color(red: 1.00, green: 0.38, blue: 0.47), Color(red: 0.72, green: 0.27, blue: 0.93)]
        case .analyze: [Color(red: 0.55, green: 0.42, blue: 1.00), Color(red: 0.25, green: 0.56, blue: 1.00)]
        case .optimize: [Color(red: 1.00, green: 0.80, blue: 0.20), Color(red: 1.00, green: 0.45, blue: 0.25)]
        case .status: [Color(red: 0.30, green: 0.85, blue: 0.40), Color(red: 0.10, green: 0.70, blue: 0.80)]
        case .history: [Color(red: 0.60, green: 0.62, blue: 0.70), Color(red: 0.38, green: 0.42, blue: 0.58)]
        }
    }

    var tint: Color { colors[1] }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    static let groups: [(String, [AppSection])] = [
        ("", [.overview]),
        ("Cleanup", [.clean, .purge, .installers]),
        ("Applications", [.uninstall]),
        ("Disk", [.analyze]),
        ("Performance", [.optimize, .status]),
        ("Activity", [.history]),
    ]
}
