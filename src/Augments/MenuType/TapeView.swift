import AppKit
import SwiftUI

/// Layout maths for the tape.
///
/// The tape is monospaced, so word widths are computed from character counts
/// rather than measured. Using one `NSFont` for both the maths and the text is
/// what keeps the offset and the glyphs in agreement.
enum Tape {
    static let contentWidth: CGFloat = 302   // panel 330 minus 2 * 14 padding
    static let height: CGFloat = 46
    /// Where the caret sits, as a percentage of the tape width — monkeytype's
    /// `tapeMargin`. They default to 50, but their tape is a full page width;
    /// at 302pt that would leave barely one word visible ahead, so this is
    /// tuned to keep roughly three words in view.
    static let marginPercent: CGFloat = 22
    static var anchor: CGFloat { contentWidth * marginPercent / 100 }
    static let wordGap: CGFloat = 11
    static let charPadX: CGFloat = 2
    static let charPadY: CGFloat = 2
    static let fontSize: CGFloat = 21

    static let nsFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
    static var swiftUIFont: Font { Font(nsFont) }

    static let charWidth: CGFloat = {
        ("0" as NSString).size(withAttributes: [.font: nsFont]).width
    }()

    static var cellWidth: CGFloat { charWidth + charPadX * 2 }

    static func width(of word: String) -> CGFloat {
        CGFloat(max(word.count, 1)) * cellWidth
    }

    /// How far to pull the tape left.
    ///
    /// This is monkeytype's `tapeMode: "letter"`: `wordsBeforeActive + width of
    /// the letters already typed in the current word`. Including the typed
    /// letters is what makes the tape scroll letter by letter instead of
    /// jumping a whole word at a time.
    static func offset(pastWords: Int, typedLetters: Int, in tape: [TapeWord]) -> CGFloat {
        let before = tape.prefix(pastWords).reduce(0) { $0 + width(of: $1.text) + wordGap }
        return before + CGFloat(typedLetters) * cellWidth
    }
}

/// Monkeytype's letter-mode tape: the words scroll past a fixed caret, one
/// character at a time, so the letter you're about to type stays put.
struct TapeView: View {
    @ObservedObject var engine: TypingEngine

    var body: some View {
        // Deliberately NOT zeroed when the word completes: keeping the full
        // typed length holds the tape at the end of the finished word instead of
        // snapping back to its start until space moves on.
        let offset = Tape.offset(pastWords: engine.currentIndex,
                                 typedLetters: engine.typed.count,
                                 in: engine.tape)
        let currentIndex = engine.currentIndex

        return ZStack(alignment: .leading) {
            HStack(spacing: Tape.wordGap) {
                ForEach(Array(engine.tape.enumerated()), id: \.element.id) { index, word in
                    wordView(word, tapeIndex: index, currentIndex: currentIndex)
                }
            }
            .fixedSize()
            .offset(x: Tape.anchor - offset)
            .animation(.easeOut(duration: 0.12), value: offset)
            .frame(width: Tape.contentWidth, height: Tape.height, alignment: .leading)
            .clipped()
            .mask(edgeFade)

            // The caret the tape scrolls past, outside the mask so it stays
            // crisp. When the word is finished it becomes a tick in exactly the
            // same slot, so the tape doesn't move.
            Group {
                if engine.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.accent)
                } else {
                    Rectangle()
                        .fill(Palette.accent.opacity(0.55))
                        .frame(width: 1.5, height: Tape.fontSize * 1.4)
                }
            }
            .frame(width: 16, height: Tape.fontSize * 1.4)
            .offset(x: Tape.anchor - 8)
        }
        .frame(width: Tape.contentWidth, height: Tape.height)
        .background(RoundedRectangle(cornerRadius: 11).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.stroke, lineWidth: 1))
    }

    /// Fade at the edges, like monkeytype's ribbon mask.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.95),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    @ViewBuilder
    private func wordView(_ word: TapeWord, tapeIndex: Int, currentIndex: Int) -> some View {
        let isCurrent = tapeIndex == currentIndex
        let isPast = tapeIndex < currentIndex

        HStack(spacing: 0) {
            ForEach(Array(Array(word.text).enumerated()), id: \.offset) { charIndex, char in
                Text(String(char))
                    .font(Tape.swiftUIFont)
                    .foregroundStyle(color(for: char, isCurrent: isCurrent, isPast: isPast,
                                           word: word, charIndex: charIndex))
                    .padding(.horizontal, Tape.charPadX)
                    .padding(.vertical, Tape.charPadY)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(cursorBackground(isCurrent: isCurrent, charIndex: charIndex))
                    )
            }
        }
    }

    private func color(for char: Character, isCurrent: Bool, isPast: Bool,
                       word: TapeWord, charIndex: Int) -> Color {
        if isPast {
            return word.hadError ? Palette.error.opacity(0.55) : Palette.dim.opacity(0.7)
        }
        if !isCurrent {
            return Palette.dim.opacity(0.55)
        }

        // In everywhere mode you're watching the menu bar rather than the panel,
        // so the emphasis is inverted: what's left to type is bright, what you've
        // already typed recedes. Finishing never goes green — the tick says that.
        let inverted = engine.isArmed
        switch engine.state(at: charIndex) {
        case .pending: return inverted ? Palette.text : Palette.dim
        case .correct: return inverted ? Palette.dim.opacity(0.75) : Palette.text
        case .wrong: return Palette.error
        case .cursor: return Palette.text
        }
    }

    private func cursorBackground(isCurrent: Bool, charIndex: Int) -> Color {
        guard isCurrent, engine.state(at: charIndex) == .cursor else { return .clear }
        return Palette.accent.opacity(0.28)
    }
}
