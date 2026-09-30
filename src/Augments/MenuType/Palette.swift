import AppKit
import SwiftUI

/// Panel colours, resolved against the effective appearance so light and dark
/// mode both work. Built from dynamic `NSColor`s, so the system swaps them
/// automatically rather than the view having to pick a palette.
enum Palette {
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func grey(_ light: CGFloat, _ dark: CGFloat, alpha: CGFloat = 1) -> Color {
        dynamic(NSColor(white: light, alpha: alpha), NSColor(white: dark, alpha: alpha))
    }

    static let background = grey(0.98, 0.075)
    static let card = dynamic(NSColor(white: 0.0, alpha: 0.045), NSColor(white: 1.0, alpha: 0.055))
    static let stroke = dynamic(NSColor(white: 0.0, alpha: 0.10), NSColor(white: 1.0, alpha: 0.08))
    static let text = grey(0.08, 0.96)
    static let dim = grey(0.45, 0.34)
    static let accent = dynamic(NSColor(red: 0.06, green: 0.52, blue: 0.42, alpha: 1),
                                NSColor(red: 0.44, green: 0.85, blue: 0.72, alpha: 1))
    static let error = dynamic(NSColor(red: 0.80, green: 0.16, blue: 0.16, alpha: 1),
                               NSColor(red: 0.98, green: 0.42, blue: 0.42, alpha: 1))
}

