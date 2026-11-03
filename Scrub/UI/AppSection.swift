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
        case .uninstall: "Applications"
        case .analyze: "Space Lens"
        case .optimize: "Maintenance"
        case .status: "Activity"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .clean: "sparkles"
        case .purge: "hammer"
        case .installers: "shippingbox"
        case .uninstall: "app.badge.checkmark"
        case .analyze: "square.grid.3x3.topleft.filled"
        case .optimize: "wrench.and.screwdriver"
        case .status: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        }
    }

    static let groups: [(String, [AppSection])] = [
        ("", [.overview]),
        ("Clean Up", [.clean, .purge, .installers]),
        ("Manage", [.uninstall, .analyze]),
        ("Performance", [.optimize, .status]),
        ("", [.history]),
    ]
}

extension CleanGroup {
    /// Colors used for storage bars and legends; plain system colors so they adapt to appearance.
    var color: Color {
        switch self {
        case .system: .blue
        case .browsers: .cyan
        case .developer: .indigo
        case .apps: .purple
        case .leftovers: .orange
        case .installers: .green
        case .trash: .pink
        case .separately: .gray
        }
    }
}
