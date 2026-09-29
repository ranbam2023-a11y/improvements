//
//  Detector.swift — turns raw contact frames into gestures.
//
//  A gesture is "N fingers landed, then all lifted within a short window".
//  Two flavours are recognised:
//
//    tap   — fingers land and lift quickly without moving much
//    pinch — fingers land spread out and pull together before lifting
//
//  Everything is tunable from the UI, so high-five aficionados who use four
//  fingers, or who prefer a slower pinch, can adjust it without rebuilding.
//

import Foundation

/// User-tunable detection parameters.
struct GestureConfig {
    enum Gesture: String, CaseIterable, Identifiable {
        case tap = "Tap"
        case pinch = "Pinch"
        case both = "Tap or Pinch"
        var id: String { rawValue }
        var allowsTap: Bool { self != .pinch }
        var allowsPinch: Bool { self != .tap }
    }

    var requiredFingers: Int = 5
    var gesture: Gesture = .both

    var tapMaxDuration: Double = 0.50      // seconds, from peak contact to all-up
    var tapMaxDrift: Float = 0.06          // centroid movement, 0…1 of trackpad
    var pinchMaxDuration: Double = 0.90
    var pinchShrink: Float = 0.70          // spread must fall below this fraction of peak

    var cooldown: Double = 0.60            // seconds between accepted gestures
}

final class Detector {
    enum Kind: String { case tap, pinch }

    var config = GestureConfig()
    var isEnabled = true
    var onGesture: ((Kind, Int, Double) -> Void)?

    private let lock = NSLock()

    // State for the gesture currently in progress.
    private var maxCount = 0
    private var baseTime: Double = 0
    private var baseCentroid: (x: Float, y: Float) = (0, 0)
    private var baseSpread: Float = 0
    private var maxDrift: Float = 0
    private var minSpread: Float = .greatestFiniteMagnitude
    private var lastFire: Double = 0

    private(set) var fireCount = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        clear()
    }

    private func clear() {
        maxCount = 0
        maxDrift = 0
        baseSpread = 0
        minSpread = .greatestFiniteMagnitude
    }

    func handle(touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        // Collect live contacts.
        var pts: [(Float, Float)] = []
        if let touches = touches {
            for i in 0..<count {
                let t = touches[i]
                if t.state == 3 || t.state == 4 {                 // MakeTouch / Touching
                    pts.append((t.normalizedVector.position.x, t.normalizedVector.position.y))
                }
            }
        }

        lock.lock(); defer { lock.unlock() }

        if !isEnabled {
            clear()
            return
        }

        let now = timestamp
        let fingers = pts.count

        // Fingers are up: decide whether the gesture that just ended qualifies.
        if fingers == 0 {
            defer { clear() }
            guard maxCount > 0 else { return }

            let cfg = config
            let duration = now - baseTime
            let enoughFingers = maxCount >= cfg.requiredFingers
            guard enoughFingers, now - lastFire > cfg.cooldown else { return }

            let isTap = cfg.gesture.allowsTap
                && duration < cfg.tapMaxDuration
                && maxDrift < cfg.tapMaxDrift

            let isPinch = cfg.gesture.allowsPinch
                && duration < cfg.pinchMaxDuration
                && baseSpread > 0
                && minSpread < baseSpread * cfg.pinchShrink

            guard isTap || isPinch else { return }

            lastFire = now
            fireCount += 1
            onGesture?(isTap ? .tap : .pinch, maxCount, duration)
            return
        }

        // Fingers down: track the centroid and spread of this contact group.
        let cx = pts.reduce(0) { $0 + $1.0 } / Float(fingers)
        let cy = pts.reduce(0) { $0 + $1.1 } / Float(fingers)
        var spread: Float = 0
        for p in pts { spread += hypot(p.0 - cx, p.1 - cy) }
        spread /= Float(fingers)

        if fingers > maxCount {
            // A new peak: re-baseline so a gesture is measured from its fullest contact.
            maxCount = fingers
            baseTime = now
            baseCentroid = (cx, cy)
            baseSpread = spread
            maxDrift = 0
            minSpread = spread
        } else {
            let drift = hypot(cx - baseCentroid.x, cy - baseCentroid.y)
            if drift > maxDrift { maxDrift = drift }
            if spread < minSpread { minSpread = spread }
        }
    }
}
