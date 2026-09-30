import AppKit
import SwiftUI

/// Local UI state. A class (rather than `@State`) because the CommandLineTools
/// SDK can't load SwiftUI's `@State` macro plugin.
private final class PopoverUI: ObservableObject {
    @Published var showStats = false
    @Published var showPrevious = false
    @Published var showSettings = false
    @Published var confirmingReset = false
}

struct PopoverView: View {
    @ObservedObject var engine: TypingEngine
    @ObservedObject var stats: StatsStore

    @StateObject private var ui = PopoverUI()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TapeView(engine: engine)
            liveMetrics
            DisclosureGroup(isExpanded: $ui.showStats) {
                statsGrid.padding(.top, 8)
            } label: {
                sectionLabel("Stats", peek: stats.bestWPM > 0 ? "best \(Int(stats.bestWPM)) wpm" : nil)
            }
            DisclosureGroup(isExpanded: $ui.showPrevious) {
                previousList.padding(.top, 8)
            } label: {
                sectionLabel("Previous words", peek: "\(stats.results.count)")
            }
            DisclosureGroup(isExpanded: $ui.showSettings) {
                settings.padding(.top, 8)
            } label: {
                sectionLabel("Settings", peek: engine.wordList.title)
            }
            footer
                .padding(.top, 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 330)
        .background(Palette.background)
        .preferredColorScheme(colorScheme)
        // Keeps keyboard focus inside the popover so keystrokes reach us.
        .background(KeyFocusView())
    }

    private var colorScheme: ColorScheme? {
        switch engine.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Header (kept deliberately small)

    private var header: some View {
        HStack(spacing: 7) {
            Text("MenuType")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)

            Spacer(minLength: 6)

            Text("In app")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(engine.isArmed ? Palette.dim : Palette.text)
            Toggle("", isOn: armBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Palette.accent)
                .help(engine.isArmed
                      ? "Everywhere: keystrokes are captured system-wide (needs Accessibility). Auto-off after 60s idle."
                      : "In app: words only fill in while this panel is open")
            Text("Everywhere")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(engine.isArmed ? Palette.text : Palette.dim)
        }
    }

    /// The controller is the authority on arming (it owns the permission check),
    /// so the toggle asks rather than sets.
    private var armBinding: Binding<Bool> {
        Binding(get: { engine.isArmed }, set: { _ in engine.toggleArm() })
    }

    private func sectionLabel(_ title: String, peek: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.text)
            if let peek {
                Text(peek)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.dim)
            }
        }
    }

    // MARK: - Live metrics

    private var liveMetrics: some View {
        HStack(spacing: 8) {
            MetricTile(label: "WPM",
                       value: engine.hasStarted || engine.isComplete
                           ? String(format: "%.0f", engine.liveWPM) : "—",
                       tint: Palette.text)
            MetricTile(label: "ACCURACY",
                       value: engine.hasStarted || engine.isComplete
                           ? String(format: "%.0f%%", engine.liveAccuracy) : "—",
                       tint: accuracyTint(engine.liveAccuracy))
            MetricTile(label: "WORDS TODAY",
                       value: "\(stats.wordsToday)",
                       tint: Palette.text)
        }
    }

    private func accuracyTint(_ accuracy: Double) -> Color {
        guard engine.hasStarted || engine.isComplete else { return Palette.text }
        if accuracy >= 98 { return Palette.accent }
        if accuracy >= 90 { return .yellow }
        return Palette.error
    }

    // MARK: - Settings dropdown

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Word list")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
                Spacer(minLength: 4)
                wordListMenu
            }
            HStack(spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
                Spacer(minLength: 4)
                appearancePicker
            }
        }
    }

    /// A `Menu` rather than a `Picker`: the native popup button draws its own
    /// light bezel, which fights the panel. This one is filled with the panel
    /// background so it blends in.
    private var wordListMenu: some View {
        Menu {
            ForEach(WordList.allCases) { list in
                Button {
                    engine.setWordList(list)
                } label: {
                    Text(list == engine.wordList ? "✓  \(list.title)" : "     \(list.title)")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(engine.wordList.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Palette.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.background))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.stroke, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var appearancePicker: some View {
        Picker("", selection: appearanceBinding) {
            ForEach(Appearance.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
    }

    private var appearanceBinding: Binding<Appearance> {
        Binding(get: { engine.appearance }, set: { engine.setAppearance($0) })
    }

    // MARK: - Stats dropdown

    private var statsGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricTile(label: "BEST WPM",
                           value: stats.bestWPM > 0 ? String(format: "%.0f", stats.bestWPM) : "—",
                           tint: Palette.accent)
                MetricTile(label: "AVG WPM",
                           value: stats.averageWPM > 0 ? String(format: "%.0f", stats.averageWPM) : "—",
                           tint: Palette.text)
                MetricTile(label: "AVG ACC",
                           value: stats.averageAccuracy > 0 ? String(format: "%.0f%%", stats.averageAccuracy) : "—",
                           tint: Palette.text)
            }
            HStack(spacing: 8) {
                MetricTile(label: "WORDS", value: "\(stats.lifetimeWords)", tint: Palette.text)
                MetricTile(label: "STREAK", value: "\(stats.streak)",
                           tint: stats.streak > 0 ? Palette.accent : Palette.dim)
                MetricTile(label: "BEST STREAK", value: "\(stats.bestStreak)", tint: Palette.text)
            }
            Text("Best and average are measured over \(StatsStore.wpmWindow) words, not one.")
                .font(.system(size: 9))
                .foregroundStyle(Palette.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Previous words dropdown

    private var previousList: some View {
        VStack(spacing: 5) {
            if stats.recent.isEmpty {
                Text("Nothing yet — finish a word.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(stats.recent.prefix(5)) { result in
                    HStack(spacing: 6) {
                        Text(result.word)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 4)
                        Text(String(format: "%.0f wpm", result.wpm))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.accent)
                        Text(String(format: "%.0f%%", result.accuracy))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(result.isPerfect ? Palette.dim : .yellow)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let warning = engine.armWarning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("New word") { engine.nextWord() }
                Spacer(minLength: 4)
                if ui.confirmingReset {
                    Button("Really reset?") {
                        stats.reset()
                        engine.nextWord()
                        ui.confirmingReset = false
                    }
                    .foregroundStyle(Palette.error)
                    Button("Cancel") { ui.confirmingReset = false }
                } else {
                    Button("Reset stats") { ui.confirmingReset = true }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.text)

            Text("space next word  ·  ⌫ fix typo  ·  esc skip")
                .font(.system(size: 10))
                .foregroundStyle(Palette.dim)
        }
    }
}

// MARK: - Small components

private struct MetricTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.stroke, lineWidth: 1))
    }
}

/// Invisible first responder that keeps the popover window key so the
/// local key monitor actually receives events. It swallows unhandled keys
/// to avoid the system beep; ⌘-shortcuts are handled earlier by the window.
private struct KeyFocusView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FocusNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class FocusNSView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            // The local monitor already consumed anything we care about.
        }
    }
}
