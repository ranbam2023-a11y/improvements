import AppKit
import Combine
import Foundation

/// How a single character of the target word should be drawn.
enum CharState {
    case pending
    case correct
    case wrong
    case cursor
}

/// One word on the tape.
///
/// Carries a stable `id` for its whole life, including when it graduates from
/// the current word to a past one — that's what lets SwiftUI animate the tape
/// sliding rather than rebuilding it every keystroke.
struct TapeWord: Identifiable, Equatable {
    let id: UUID
    var text: String
    /// Only meaningful once `isPast`.
    var hadError: Bool = false
    var isPast: Bool = false

    init(id: UUID = UUID(), text: String, hadError: Bool = false, isPast: Bool = false) {
        self.id = id
        self.text = text
        self.hadError = hadError
        self.isPast = isPast
    }
}

/// The typing state machine.
///
/// Holds the tape (past words, the current word, upcoming words), the keystroke
/// log for the current word, and the derived live metrics (WPM / accuracy /
/// elapsed).
///
/// There are two input paths, and they behave differently on purpose:
///
///  * **Local (popover open)** — you clicked in and are obviously playing, so
///    every keystroke counts immediately, typos included.
///  * **Global (everywhere mode)** — the app is listening to the whole system,
///    so a word starts *asleep*. Keystrokes are ignored until your typed prefix
///    matches the word, and the word falls asleep again after a short pause.
///    That's what stops stray typing in other apps from painting the menu bar
///    red.
final class TypingEngine: ObservableObject {

    /// Words in the tape window: current + upcoming.
    static let queueLength = 3
    /// Past words kept on the tape so it can slide instead of snapping.
    static let historyLimit = 3
    /// Everywhere mode: matching leading characters needed to wake a word up.
    private static let commitThreshold = 2
    /// Everywhere mode: pause after which a live word goes back to sleep.
    private static let disengageAfter: TimeInterval = 2.5

    private static let wordListKey = "menutype.wordlist"
    private static let appearanceKey = "menutype.appearance"

    // MARK: - Published state

    /// Past words, then the current word, then upcoming ones.
    @Published private(set) var tape: [TapeWord]
    @Published private(set) var typed: [Character] = []
    @Published private(set) var isComplete = false
    @Published private(set) var lastResult: WordResult?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var wordList: WordList
    /// Panel appearance, chosen in Settings.
    @Published private(set) var appearance: Appearance

    /// True while system-wide ("everywhere") capture is switched on.
    @Published private(set) var isArmed = false
    /// Everywhere mode only: true once a word has woken up and is really being played.
    @Published private(set) var isEngaged = false
    /// Set by the controller: whether the popover panel is on screen.
    @Published var isPanelOpen = false
    /// Human-readable reason the app can't arm everywhere mode, if any.
    @Published var armWarning: String?

    /// Timestamp of the last keystroke we actually acted on.
    private(set) var lastInputAt: Date?

    let stats: StatsStore
    /// Controller hook so the view can request arming without owning the controller.
    var requestArm: ((Bool) -> Void)?

    // MARK: - Private

    private let defaults: UserDefaults
    private var startedAt: Date?
    private var probeStartedAt: Date?
    private var correctStrokes = 0
    private var totalStrokes = 0
    private var wordHadError = false
    private var ticker: Timer?
    private var sleepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(stats: StatsStore = StatsStore(),
         defaults: UserDefaults = .standard,
         queueLength: Int = TypingEngine.queueLength) {
        self.stats = stats
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.wordListKey).flatMap(WordList.init(rawValue:))
        self.wordList = stored ?? .english200
        self.appearance = defaults.string(forKey: Self.appearanceKey)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        self.tape = Words.randomQueue(count: max(1, queueLength), from: stored ?? .english200)
            .map { TapeWord(text: $0) }
        stats.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    // MARK: - The tape

    /// Index of the word being typed: the first one that isn't past.
    var currentIndex: Int { tape.firstIndex { !$0.isPast } ?? 0 }

    var target: String { tape.indices.contains(currentIndex) ? tape[currentIndex].text : "word" }
    var targetChars: [Character] { Array(target) }
    var past: [TapeWord] { Array(tape.prefix(currentIndex)) }
    var upcoming: [TapeWord] { tape.indices.contains(currentIndex) ? Array(tape.dropFirst(currentIndex + 1)) : [] }

    /// Move on to the next word — also the "skip" action.
    func nextWord() {
        guard !tape.isEmpty else { return }
        let index = currentIndex

        if isComplete {
            // Graduates to the past: same id, so the tape slides it out.
            tape[index].isPast = true
            tape[index].hadError = wordHadError
            tape.append(TapeWord(text: freshWord()))
        } else {
            // Skipped without finishing: swap in place, nothing recorded.
            tape[index] = TapeWord(text: freshWord())
        }

        // Trim old words off the front; they're already scrolled out of view.
        let pastCount = tape.prefix { $0.isPast }.count
        if pastCount > Self.historyLimit {
            tape.removeFirst(pastCount - Self.historyLimit)
        }

        resetProgress()
        isEngaged = false
    }

    /// Switch pools and start a clean tape.
    func setWordList(_ list: WordList) {
        guard list != wordList else { return }
        wordList = list
        defaults.set(list.rawValue, forKey: Self.wordListKey)
        tape = Words.randomQueue(count: max(1, Self.queueLength), from: list).map { TapeWord(text: $0) }
        resetProgress()
        isEngaged = false
        objectWillChange.send()
    }

    func setAppearance(_ value: Appearance) {
        guard value != appearance else { return }
        appearance = value
        defaults.set(value.rawValue, forKey: Self.appearanceKey)
        objectWillChange.send()
    }

    private func freshWord() -> String {
        Words.random(for: wordList, avoiding: Set(tape.map(\.text)))
    }

    // MARK: - Derived metrics

    var correctChars: Int {
        zip(typed, targetChars).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
    }

    /// Live words-per-minute for the current word (standard: 5 chars == 1 word).
    var liveWPM: Double {
        guard let startedAt, !typed.isEmpty else { return 0 }
        let seconds = max(Date().timeIntervalSince(startedAt), 0.25)
        return (Double(correctChars) / 5.0) / (seconds / 60.0)
    }

    var liveAccuracy: Double {
        totalStrokes == 0 ? 100 : Double(correctStrokes) / Double(totalStrokes) * 100
    }

    var hasStarted: Bool { startedAt != nil }

    /// Whether the word should show a cursor — i.e. whether we're actually listening.
    var isLive: Bool { isPanelOpen || isEngaged }

    func state(at index: Int) -> CharState {
        if isComplete { return .correct }
        if index < typed.count {
            return typed[index] == targetChars[index] ? .correct : .wrong
        }
        if index == typed.count && isLive { return .cursor }
        return .pending
    }

    // MARK: - Input

    /// Feed a key event in. Returns true when the event was consumed.
    @discardableResult
    func handle(event: NSEvent, global: Bool = false) -> Bool {
        guard event.type == .keyDown else { return false }
        if global && !isEngaged && !isPanelOpen {
            return probeEvent(event)
        }
        return activeEvent(event)
    }

    /// Everywhere mode, word asleep: only letters that continue the word matter.
    /// Anything else is ignored outright — no strokes, no red.
    private func probeEvent(_ event: NSEvent) -> Bool {
        guard !isShortcutOrRepeat(event) else { return false }
        guard let ch = letter(from: event) else { return false }
        probe(ch)
        return true
    }

    /// Awake: the keystrokes are real typing.
    private func activeEvent(_ event: NSEvent) -> Bool {
        let code = event.keyCode
        // Only the focused panel, or a woken-up word, may drive the tape.
        let canCommandQueue = isPanelOpen || isEngaged

        // Delete / forward-delete: fix a typo (not once the word is done).
        if code == 51 || code == 117 {
            guard canCommandQueue, !isComplete, !typed.isEmpty else { return false }
            backspace()
            return true
        }

        // Escape / Return / Tab: skip to a new word.
        if code == 53 || code == 36 || code == 48 {
            guard canCommandQueue else { return false }
            nextWord()
            return true
        }

        // Space is what moves you on to the next word.
        if code == 49 {
            guard canCommandQueue else { return false }
            if isComplete || typed.isEmpty {
                nextWord()
                return true
            }
            return false
        }

        guard !isShortcutOrRepeat(event) else { return false }
        guard let ch = letter(from: event) else { return false }

        // The word is finished; space moves on, letters don't.
        guard !isComplete else { return false }

        record(ch)
        return true
    }

    private func isShortcutOrRepeat(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            return true
        }
        return event.isARepeat
    }

    private func letter(from event: NSEvent) -> Character? {
        guard let raw = event.charactersIgnoringModifiers,
              let ch = raw.lowercased().first,
              ch.isLetter else { return nil }
        return ch
    }

    /// Everywhere mode: extend the matched prefix, or give up quietly.
    private func probe(_ ch: Character) {
        guard typed.count < targetChars.count else {
            resetProgress()
            return
        }

        guard ch == targetChars[typed.count] else {
            // Not our word — go back to sleep without recording an error.
            resetProgress()
            return
        }

        if typed.isEmpty { probeStartedAt = Date() }
        typed.append(ch)
        lastInputAt = Date()

        guard typed.count >= Self.commitThreshold else { return }

        // Enough of a match: treat this as a real attempt from here on.
        isEngaged = true
        startedAt = probeStartedAt ?? Date()
        correctStrokes = typed.count
        totalStrokes = typed.count
        startTicker()
        checkForCompletion()
    }

    /// Normal keystroke handling for an awake word.
    private func record(_ ch: Character) {
        guard typed.count < targetChars.count else { return }

        if startedAt == nil {
            startedAt = Date()
            startTicker()
        }

        lastInputAt = Date()
        typed.append(ch)
        totalStrokes += 1

        let index = typed.count - 1
        if ch == targetChars[index] {
            correctStrokes += 1
        } else {
            wordHadError = true
        }

        checkForCompletion()
    }

    private func backspace() {
        guard !typed.isEmpty else { return }
        lastInputAt = Date()
        typed.removeLast()
        if typed.isEmpty {
            startedAt = nil
            stopTicker()
            elapsed = 0
        }
    }

    // MARK: - Completion

    private func checkForCompletion() {
        guard typed.count == targetChars.count, correctChars == targetChars.count else { return }
        finish()
    }

    private func finish() {
        guard let startedAt else { return }
        let seconds = max(Date().timeIntervalSince(startedAt), 0.25)
        let wpm = (Double(targetChars.count) / 5.0) / (seconds / 60.0)
        let accuracy = totalStrokes == 0 ? 100 : Double(correctStrokes) / Double(totalStrokes) * 100

        let result = WordResult(
            word: target,
            wpm: wpm,
            accuracy: accuracy,
            seconds: seconds,
            strokes: totalStrokes,
            correctStrokes: correctStrokes
        )

        lastResult = result
        isComplete = true
        elapsed = seconds
        stopTicker()
        stats.record(result, hadError: wordHadError)

        // No auto-advance: space moves you on to the next word.
    }

    // MARK: - Progress

    /// Wipe the current word's typing without changing the tape.
    func resetProgress() {
        typed = []
        isComplete = false
        startedAt = nil
        probeStartedAt = nil
        elapsed = 0
        correctStrokes = 0
        totalStrokes = 0
        wordHadError = false
        stopTicker()
        objectWillChange.send()
    }

    func panelDidClose() {
        isPanelOpen = false
        isEngaged = false
        // Never leave half-typed or red text sitting in the menu bar.
        if !isComplete { resetProgress() }
        objectWillChange.send()
    }

    func panelDidOpen() {
        isPanelOpen = true
        isEngaged = false
        resetProgress()
        objectWillChange.send()
    }

    // MARK: - Sleep / wake (everywhere mode)

    /// Put a forgotten word back to sleep so it stops absorbing keystrokes.
    func sleepIfIdle() {
        guard isArmed, isEngaged, !isPanelOpen, let last = lastInputAt else { return }
        guard Date().timeIntervalSince(last) > Self.disengageAfter else { return }
        if isComplete {
            nextWord()
        } else {
            resetProgress()
            isEngaged = false
        }
    }

    /// Runs continuously while everywhere mode is armed; `sleepIfIdle` decides
    /// whether there's actually anything to put to sleep.
    private func startSleepTimer() {
        guard sleepTimer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.sleepIfIdle()
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    private func stopSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
    }

    // MARK: - Arming

    func toggleArm() {
        requestArm?(!isArmed)
    }

    func setArmed(_ armed: Bool) {
        isArmed = armed
        armWarning = nil
        isEngaged = false
        if armed {
            lastInputAt = Date()
            startSleepTimer()
        } else {
            stopSleepTimer()
            resetProgress()
        }
        objectWillChange.send()
    }

    func disarm() {
        guard isArmed else { return }
        setArmed(false)
    }

    // MARK: - Ticker (live elapsed time)

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            self.elapsed = Date().timeIntervalSince(startedAt)
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
