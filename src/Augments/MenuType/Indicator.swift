import AppKit

/// The menu bar's leading status slot in everywhere mode: a dot while you type,
/// a tick once the word is finished.
///
/// The two symbols have different natural widths, so each is drawn into an image
/// attachment pinned to the same bounds. That is what stops the menu bar
/// twitching sideways when the word completes — see `IndicatorTests` in the
/// build checks, which asserts the two are the same width.
enum Indicator {
    static let slot = CGSize(width: 11, height: 11)

    static func attributed(complete: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment(complete: complete)))
        result.append(NSAttributedString(string: " ", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
        ]))
        return result
    }

    private static func attachment(complete: Bool) -> NSTextAttachment {
        let name = complete ? "checkmark" : "circle.fill"
        let attachment = NSTextAttachment()

        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: slot.height,
                                                                 weight: .bold)) {
            let image = NSImage(size: slot)
            image.lockFocus()
            let scale = min(slot.width / max(symbol.size.width, 1),
                            slot.height / max(symbol.size.height, 1))
            let drawn = CGSize(width: symbol.size.width * scale,
                               height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: (slot.width - drawn.width) / 2,
                                   y: (slot.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height),
                        from: .zero, operation: .sourceOver, fraction: 1)
            // Tint the glyph, preserving its alpha.
            NSColor.systemGreen.set()
            NSRect(origin: .zero, size: slot).fill(using: .sourceAtop)
            image.unlockFocus()
            attachment.image = image
        }

        attachment.bounds = CGRect(x: 0, y: -1, width: slot.width, height: slot.height)
        return attachment
    }
}
