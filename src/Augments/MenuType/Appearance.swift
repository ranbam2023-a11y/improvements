import Foundation

/// Panel appearance, chosen in Settings.
///
/// Deliberately free of SwiftUI so the engine can own it; the view maps it to
/// a `ColorScheme`.
enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
