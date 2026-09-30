# Ran's macOS Improvements

A small app that collects tiny fixes for macOS — we call them **augments**.
Each one is a single behaviour you can switch on or off, with a description of
what it does and settings you can edit.

The window lists every augment, shows whether it's on, and lets you tune it.
Closing the window leaves the app running in the menu bar, so your augments
keep working; quit from the menu bar icon or with ⌘Q.

## Augments

### High Five

Do something with a five-finger tap (or pinch) on the trackpad. Pick one of
three actions:

| Action | What it does | Permissions |
| --- | --- | --- |
| **Open Raycast** | Opens Raycast's launcher through its own `raycast://` link | none |
| **Open an app** | Launches or activates any app, by name, bundle id or path | none |
| **Send a keyboard shortcut** | Presses a shortcut such as `cmd+shift+4` or `⌥F` | Accessibility |

Opening Raycast with its link rather than a keystroke means it works with **any
Raycast keybind**, including if you change it later, and never asks for
permission. Sending a shortcut is the only action that needs Accessibility: the
app notices when it's missing, offers a button to open the right settings pane,
and includes a **Test** button so you can try the shortcut without the trackpad.

Other settings: how many fingers are required, tap vs. pinch, and the timing
thresholds for each.

### MenuType

A typing trainer in the menu bar. A random word sits up there and fills in as
you type — click it for your speed and accuracy. Space moves to the next word,
⌫ fixes a typo, esc skips.

It only listens while the panel is open by default, which needs no permissions.
Flip the panel's switch to **Everywhere** and it follows you into any app — that
mode captures keystrokes system-wide, so it needs Accessibility, and it switches
itself off after a minute of not typing.

Word list and panel appearance are chosen in the panel's own Settings section.
Its stats and settings live in the augment's own store, so turning the augment
off clears them along with everything else.

The app is plain AppKit — no SwiftUI, no Xcode project — so it builds with
nothing but the command line tools.

## Install

```bash
git clone https://github.com/ranbam2023-a11y/improvements.git
cd improvements
./install.sh
```

Or build a disk image and drag it in yourself:

```bash
./build.sh --dmg      # → dist/Improvements-1.0.dmg
```

Because the app is ad-hoc signed (not notarised), a downloaded copy needs one
Gatekeeper nudge:

```bash
xattr -dr com.apple.quarantine /Applications/Improvements.app
```

…or right-click the app and choose **Open** once.

`install.sh` installs to **/Applications** (falling back to `~/Applications` if
that isn't writable), registers a login item, and removes the old standalone
**HighFive** agent, since this app replaces it.

### Requirements

- macOS 13 or later
- For High Five: turn off **System Settings → Trackpad → More Gestures → Show
  Desktop**, so macOS doesn't react to five fingers at the same time. The app
  checks this and offers to do it for you.
- Only for the **keyboard shortcut** action: Accessibility permission. The app
  tells you when it's missing and can open the settings pane for you.

## Uninstall

```bash
./uninstall.sh
```

## How it fits together

```
src/
  main.swift              app bootstrap: window, menus, menu bar item
  UI.swift                sidebar, detail pane, settings controls (AppKit)
  Model.swift             augments, typed settings, persistence, login item
  AugmentData.swift       per-augment storage, wiped when an augment is off
  HighFiveAugment.swift   the first augment
  Detector.swift          contact frames → gestures (fully tunable)
  Multitouch.swift        private MultitouchSupport, dlopen'd at runtime
  Shortcut.swift          parse and post keyboard shortcuts
  Log.swift               ~/Library/Logs/Improvements.log
  mt.h                    MTTouch layout
  Augments/MenuType/      the second augment (SwiftUI panel, word list, stats)
tools/make-icon.swift     generates the app icon
Resources/Info.plist
build.sh                  build the app, or a .dmg with --dmg
install.sh / uninstall.sh
```

Settings live in `~/Library/Application Support/Improvements/config.json`.

### Adding an augment

Subclass `Augment`, describe your settings with `SettingSpec`, and start/stop
your work in `start()` / `stop()`. Add it to the list in `AppModel.init()` — the
UI builds itself from the description. See `HighFiveAugment.swift` for a worked
example, including how to declare a `Requirement` the app can check and fix.

## Licence

MIT.
