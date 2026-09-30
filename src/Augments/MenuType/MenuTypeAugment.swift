//
//  MenuTypeAugment.swift — the second augment.
//
//  A typing trainer in the menu bar: a random word lives in the menu bar and
//  fills in as you type, with speed and accuracy in a popover.
//
//  The practice settings (word list, appearance) live in the popover itself,
//  where they always have, and are stored in this augment's own data store —
//  so turning the augment off removes them along with everything else.
//

import Foundation
import AppKit
import ApplicationServices

final class MenuTypeAugment: Augment {

    private lazy var controller = MenuTypeController(defaults: MenuTypeAugment.defaults)

    /// MenuType keeps its settings and stats in a UserDefaults suite of its own,
    /// which the app deletes when the augment is turned off.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: AugmentData.suiteName(for: "menutype")) ?? .standard
    }

    init() {
        super.init(
            id: "menutype",
            name: "MenuType",
            icon: "keyboard",
            tagline: "A typing trainer that lives in your menu bar.",
            description: """
            A random word sits in your menu bar and fills in as you type — click it \
            for your speed and accuracy. Finish a word with space, fix a typo with ⌫, \
            skip with esc.

            There are two ways to play. By default it only listens while the panel is \
            open, which needs no permissions at all. Flip the panel's switch to \
            “Everywhere” and it will follow you into any app — that mode captures \
            keystrokes system-wide, so it needs the Accessibility permission, and it \
            turns itself off after a minute of not typing.

            Word list and panel appearance are chosen in the panel's own Settings \
            section. Nothing is recorded while the augment is off, and turning it off \
            clears its stored stats and settings.
            """,
            specs: []
        )
    }

    // MARK: Requirements

    override var requirements: [Requirement] {
        [Requirement(
            id: "accessibility",
            text: "Accessibility permission — only needed for the panel's “Everywhere” mode. Typing in the panel works without it.",
            isSatisfied: { AXIsProcessTrusted() },
            fixLabel: "Open Settings",
            fix: { ShortcutPoster.openPermissionSettings() }
        )]
    }

    // MARK: Lifecycle

    override func start() {
        controller.start()
        status = "In the menu bar — click the word to practise"
        Log.write("menutype started")
    }

    override func stop() {
        controller.stop()
        status = "Off"
        Log.write("menutype stopped")
    }
}
