//
//  HighFiveAugment.swift — the first augment.
//
//  A gesture on the trackpad can do one of three things:
//
//    • open Raycast (or any other link)
//    • open an app
//    • send a keyboard shortcut
//
//  The gesture is measured from raw contact frames; nothing is synthesised for
//  the first two, so they need no permissions. Sending a shortcut does need the
//  Accessibility permission, which the augment checks for and can take you to.
//

import Foundation
import AppKit
import ApplicationServices

final class HighFiveAugment: Augment {

    enum Action: String, CaseIterable {
        case raycast  = "Open Raycast"
        case app      = "Open an app"
        case shortcut = "Send a keyboard shortcut"
    }

    private let detector = Detector()
    private let fireQueue = DispatchQueue(label: "com.ranbam.improvements.highfive")

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    init() {
        super.init(
            id: "highfive",
            name: "High Five",
            icon: "hand.raised.fingers.spread.fill",
            tagline: "Do something with a five-finger trackpad tap.",
            description: """
            High Five watches the raw contact frames from your trackpad. When it \
            sees five fingertips land together and lift quickly, it does whatever \
            you asked: open Raycast, launch an app, or press a keyboard shortcut.

            Opening Raycast uses its own `raycast://` link rather than pretending \
            to press a key, so it works with any Raycast keybind and never asks \
            for permission. Opening an app is just a launcher. Sending a keyboard \
            shortcut is the one action that needs the Accessibility permission — \
            the app tries to give you a way to grant it right here.

            Pick a different number of fingers, switch between a tap and a pinch, \
            or change what it does at any time in the settings below.
            """,
            specs: [
                SettingSpec("action", "What should it do?", group: "Action",
                            help: "What happens when the gesture is detected.",
                            kind: .choice(Action.allCases.map { $0.rawValue }),
                            default: .string(Action.raycast.rawValue)),
                SettingSpec("raycastURL", "Link to open", group: "Action",
                            help: "Anything Raycast understands, e.g. raycast:// or raycast://extensions/…",
                            kind: .text(placeholder: "raycast://"), default: .string("raycast://")),
                SettingSpec("appName", "App to open", group: "Action",
                            help: "An app's name, its bundle identifier, or a full path.",
                            kind: .text(placeholder: "Safari"), default: .string("Safari")),
                SettingSpec("appBundleID", "Bundle identifier", group: "Action",
                            help: "Used to tell whether Raycast is already running.",
                            kind: .text(placeholder: "com.raycast.macos"), default: .string("com.raycast.macos")),
                SettingSpec("shortcut", "Keyboard shortcut", group: "Action",
                            help: "For example cmd+shift+4, option+f, or ⌥F. Press Test to try it without the trackpad.",
                            kind: .shortcut(placeholder: "cmd+shift+4"), default: .string("cmd+space")),
                SettingSpec("launchIfNeeded", "Launch first if it isn't running", group: "Action",
                            help: "Opening a link at a cold start can be too early for the app to show a window.",
                            kind: .toggle, default: .bool(true)),

                SettingSpec("fingers", "Fingers required", group: "Detection",
                            help: "How many fingertips must touch down together.",
                            kind: .stepper(1...10, step: 1), default: .int(5)),
                SettingSpec("gesture", "Gesture", group: "Detection",
                            help: "A tap is a quick press and release. A pinch is fingers pulling together before they lift.",
                            kind: .choice(GestureConfig.Gesture.allCases.map { $0.rawValue }),
                            default: .string(GestureConfig.Gesture.both.rawValue)),
                SettingSpec("cooldown", "Cooldown", group: "Detection",
                            help: "Ignore further gestures for this long after one fires.",
                            kind: .slider(0.1...3.0, step: 0.1, format: "%.1f s"), default: .double(0.6)),

                SettingSpec("tapMaxDuration", "Tap: longest press", group: "Fine tuning",
                            help: "How long, from the moment all fingers land, they may stay down and still count as a tap.",
                            kind: .slider(0.10...1.50, step: 0.05, format: "%.2f s"), default: .double(0.50)),
                SettingSpec("tapMaxDrift", "Tap: allowed movement", group: "Fine tuning",
                            help: "How far the group's centre may wander while tapping. Lower is stricter.",
                            kind: .slider(0.01...0.30, step: 0.01, format: "%.2f"), default: .double(0.06)),
                SettingSpec("pinchMaxDuration", "Pinch: longest press", group: "Fine tuning",
                            help: "How long a pinch may take before the fingers lift.",
                            kind: .slider(0.20...2.00, step: 0.05, format: "%.2f s"), default: .double(0.90)),
                SettingSpec("pinchShrink", "Pinch: closeness", group: "Fine tuning",
                            help: "How far the fingers must come together, as a fraction of their starting spread.",
                            kind: .slider(0.30...0.95, step: 0.05, format: "%.2f×"), default: .double(0.70))
            ]
        )

        detector.onGesture = { [weak self] kind, fingers, duration in
            guard let self = self else { return }
            self.fireQueue.async { self.fire(kind: kind, fingers: fingers, duration: duration) }
        }
        detector.config = gestureConfig()
    }

    // MARK: What the user sees

    /// Only the settings that apply to the chosen action.
    override var visibleSpecs: [SettingSpec] {
        let action = currentAction
        let optionIDs: [String]
        switch action {
        case .raycast:  optionIDs = ["raycastURL", "launchIfNeeded", "appBundleID"]
        case .app:      optionIDs = ["appName"]
        case .shortcut: optionIDs = ["shortcut"]
        }
        return specs.filter { $0.group != "Action" || $0.id == "action" || optionIDs.contains($0.id) }
    }

    override var requirements: [Requirement] {
        var items: [Requirement] = []

        items.append(Requirement(
            id: "showdesktop",
            text: "macOS's built-in “Show Desktop” gesture is off, so it doesn't react to five fingers at the same time.",
            isSatisfied: { HighFiveAugment.showDesktopIsOff() },
            fixLabel: "Turn it off",
            fix: { HighFiveAugment.disableShowDesktop() }
        ))

        if currentAction == .shortcut {
            items.append(Requirement(
                id: "accessibility",
                text: "Accessibility permission, so Improvements can send the shortcut to other apps.",
                isSatisfied: { ShortcutPoster.hasPermission },
                fixLabel: "Open Settings",
                fix: { ShortcutPoster.openPermissionSettings() }
            ))
        }

        return items
    }

    private var currentAction: Action {
        Action(rawValue: string("action")) ?? .raycast
    }

    // MARK: Show Desktop

    static func showDesktopIsOff() -> Bool {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return true }
        if let flag = dock.object(forKey: "showDesktopGestureEnabled") as? Bool { return !flag }
        if let flag = dock.object(forKey: "showDesktopGestureEnabled") as? Int { return flag == 0 }
        return true
    }

    static func disableShowDesktop() {
        Log.run("/usr/bin/defaults", ["write", "com.apple.dock", "showDesktopGestureEnabled", "-bool", "false"])
        Log.run("/usr/bin/defaults", ["write", "com.apple.AppleMultitouchTrackpad",
                                      "TrackpadFiveFingerPinchGesture", "-int", "0"])
        Log.run("/usr/bin/killall", ["Dock"])
        Log.write("disabled Show Desktop gesture")
    }

    // MARK: Lifecycle

    override func start() {
        detector.config = gestureConfig()
        detector.isEnabled = true

        let ok = Multitouch.shared.start { [weak self] touches, count, timestamp in
            self?.detector.handle(touches: touches, count: count, timestamp: timestamp)
        }

        if ok {
            let devices = Multitouch.shared.deviceCount
            status = "Listening on \(devices) trackpad device\(devices == 1 ? "" : "s") · \(currentAction.rawValue)"
            Log.write("highfive started devices=\(devices) fingers=\(detector.config.requiredFingers) gesture=\(detector.config.gesture.rawValue) action=\(currentAction.rawValue)")
        } else {
            status = "Unavailable — \(Multitouch.shared.lastError ?? "unknown error")"
            Log.write("highfive unavailable: \(Multitouch.shared.lastError ?? "unknown error")")
        }
    }

    override func stop() {
        detector.isEnabled = false
        detector.reset()
        // Turn the trackpad devices off too, so a disabled augment leaves
        // nothing running in the background.
        Multitouch.shared.stop()
        status = "Off"
        Log.write("highfive stopped")
    }

    override func didUpdateConfig() {
        detector.config = gestureConfig()
        if enabled { status = "Listening · \(currentAction.rawValue)" }
    }

    override func fireOnce() {
        fire(kind: .tap, fingers: int("fingers"), duration: 0)
    }

    // MARK: Firing

    private func gestureConfig() -> GestureConfig {
        var c = GestureConfig()
        c.requiredFingers = int("fingers")
        c.gesture = GestureConfig.Gesture(rawValue: string("gesture")) ?? .both
        c.tapMaxDuration = double("tapMaxDuration")
        c.tapMaxDrift = Float(double("tapMaxDrift"))
        c.pinchMaxDuration = double("pinchMaxDuration")
        c.pinchShrink = Float(double("pinchShrink"))
        c.cooldown = double("cooldown")
        return c
    }

    private func fire(kind: Detector.Kind, fingers: Int, duration: Double) {
        let action = currentAction
        Log.write(String(format: "fire %@ fingers=%d dur=%.3f action=%@",
                         kind.rawValue, fingers, duration, action.rawValue))

        let label = "\(kind == .tap ? "Tap" : "Pinch") · \(fingers) fingers · \(action.rawValue) · \(Self.timeFormatter.string(from: Date()))"
        DispatchQueue.main.async { [weak self] in self?.lastEvent = label }

        switch action {
        case .raycast:
            let bundleID = string("appBundleID")
            if bool("launchIfNeeded"), !bundleID.isEmpty, !Self.isRunning(bundleID) {
                Log.write("raycast not running, launching first")
                Log.run("/usr/bin/open", ["-a", "Raycast"])
                Thread.sleep(forTimeInterval: 1.2)
            }
            Log.run("/usr/bin/open", [string("raycastURL")])

        case .app:
            let name = string("appName").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                Log.write("no app configured for the app action")
                DispatchQueue.main.async { [weak self] in self?.lastEvent = "No app configured" }
                return
            }
            let status = Log.run("/usr/bin/open", ["-a", name])
            if status != 0 { Log.write("open -a \(name) exited \(status)") }

        case .shortcut:
            guard ShortcutPoster.hasPermission else {
                Log.write("shortcut skipped: no Accessibility permission")
                DispatchQueue.main.async { [weak self] in self?.lastEvent = "Needs Accessibility permission" }
                return
            }
            let text = string("shortcut")
            guard let combo = ShortcutParser.parse(text) else {
                Log.write("could not parse shortcut \"\(text)\"")
                DispatchQueue.main.async { [weak self] in self?.lastEvent = "Couldn't read “\(text)”" }
                return
            }
            ShortcutPoster.post(combo)
        }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
