import Foundation

struct WordResult: Codable, Identifiable {
    var id: UUID = UUID()
    var word: String
    var wpm: Double
    var accuracy: Double
    var seconds: Double
    var strokes: Int
    var correctStrokes: Int
    var date: Date = Date()

    var isPerfect: Bool { accuracy >= 99.99 }
}

/// All-time + recent performance, persisted to UserDefaults.
final class StatsStore: ObservableObject {
    @Published private(set) var results: [WordResult] = []
    @Published private(set) var lifetimeWords = 0
    @Published private(set) var lifetimeSeconds: Double = 0
    @Published private(set) var lifetimeStrokes = 0
    @Published private(set) var lifetimeCorrect = 0
    @Published private(set) var bestWPM: Double = 0
    @Published private(set) var bestAccuracy: Double = 0
    @Published private(set) var streak = 0
    @Published private(set) var bestStreak = 0
    /// Words finished since midnight. Rolls over on its own.
    @Published private(set) var wordsToday = 0

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxHistory = 50

    /// Best/average speed is measured over a rolling window of whole words
    /// rather than single words — a 3-letter word typed quickly produces a
    /// wildly inflated one-word WPM, so a window is what "best" should mean.
    static let wpmWindow = 5
    /// Window used for the running average.
    static let averageWindow = 10
    private var todayStamp: String

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayStamp(_ date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    private struct Snapshot: Codable {
        var results: [WordResult]
        var lifetimeWords: Int
        var lifetimeSeconds: Double
        var lifetimeStrokes: Int
        var lifetimeCorrect: Int
        var bestWPM: Double
        var bestAccuracy: Double
        var streak: Int
        var bestStreak: Int
        var wordsToday: Int
        var todayStamp: String
    }

    init(defaults: UserDefaults = .standard, storageKey: String = "menutype.stats.v2") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.todayStamp = Self.dayStamp()
        load()
    }

    // MARK: - Derived

    /// Most recent runs, newest first.
    var recent: [WordResult] { Array(results.suffix(10).reversed()) }

    var averageWPM: Double {
        Self.wpm(of: results.suffix(Self.averageWindow))
    }

    /// True average speed: total correct characters over total time.
    static func wpm(of window: ArraySlice<WordResult>) -> Double {
        let seconds = window.reduce(0) { $0 + $1.seconds }
        let correct = window.reduce(0) { $0 + $1.correctStrokes }
        guard seconds > 0, correct > 0 else { return 0 }
        return (Double(correct) / 5.0) / (seconds / 60.0)
    }

    var averageAccuracy: Double {
        let sample = results.suffix(10)
        guard !sample.isEmpty else { return 0 }
        return sample.map(\.accuracy).reduce(0, +) / Double(sample.count)
    }

    var lifetimeAccuracy: Double {
        lifetimeStrokes == 0 ? 0 : Double(lifetimeCorrect) / Double(lifetimeStrokes) * 100
    }

    // MARK: - Recording

    func record(_ result: WordResult, hadError: Bool) {
        rollTodayOver()
        wordsToday += 1
        results.append(result)
        if results.count > maxHistory {
            results.removeFirst(results.count - maxHistory)
        }

        lifetimeWords += 1
        lifetimeSeconds += result.seconds
        lifetimeStrokes += result.strokes
        lifetimeCorrect += result.correctStrokes
        if results.count >= Self.wpmWindow {
            bestWPM = max(bestWPM, Self.wpm(of: results.suffix(Self.wpmWindow)))
        }
        bestAccuracy = max(bestAccuracy, result.accuracy)

        if hadError {
            streak = 0
        } else {
            streak += 1
            bestStreak = max(bestStreak, streak)
        }

        save()
    }

    func reset() {
        results = []
        lifetimeWords = 0
        lifetimeSeconds = 0
        lifetimeStrokes = 0
        lifetimeCorrect = 0
        bestWPM = 0
        bestAccuracy = 0
        streak = 0
        bestStreak = 0
        wordsToday = 0
        defaults.removeObject(forKey: storageKey)
    }

    /// Reset the daily counter when the date changes.
    private func rollTodayOver() {
        let stamp = Self.dayStamp()
        if stamp != todayStamp {
            todayStamp = stamp
            wordsToday = 0
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        todayStamp = snap.todayStamp
        wordsToday = snap.wordsToday
        // A snapshot from a previous day starts today's count at zero.
        rollTodayOver()

        results = snap.results
        lifetimeWords = snap.lifetimeWords
        lifetimeSeconds = snap.lifetimeSeconds
        lifetimeStrokes = snap.lifetimeStrokes
        lifetimeCorrect = snap.lifetimeCorrect
        bestWPM = snap.bestWPM
        bestAccuracy = snap.bestAccuracy
        // Older builds stored a single word's best; recompute from full windows.
        if results.count >= Self.wpmWindow {
            bestWPM = stride(from: Self.wpmWindow, through: results.count, by: 1)
                .reduce(0) { best, end in max(best, Self.wpm(of: results[(end - Self.wpmWindow)..<end])) }
        } else {
            bestWPM = 0
        }
        streak = snap.streak
        bestStreak = snap.bestStreak
    }

    private func save() {
        let snap = Snapshot(
            results: results,
            lifetimeWords: lifetimeWords,
            lifetimeSeconds: lifetimeSeconds,
            lifetimeStrokes: lifetimeStrokes,
            lifetimeCorrect: lifetimeCorrect,
            bestWPM: bestWPM,
            bestAccuracy: bestAccuracy,
            streak: streak,
            bestStreak: bestStreak,
            wordsToday: wordsToday,
            todayStamp: todayStamp
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
