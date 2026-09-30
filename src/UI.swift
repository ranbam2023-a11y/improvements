//
//  UI.swift — the window, built with AppKit.
//
//  A sidebar lists the augments (and a General page); the detail pane shows
//  the selected augment's description, requirements, settings and status.
//  Controls are created from each augment's SettingSpec list, so adding a new
//  augment needs no UI code.
//

import AppKit

// MARK: - Small helpers

/// Lets AppKit controls call a Swift closure without target/action plumbing.
final class ActionProxy: NSObject {
    private let handler: (Any?) -> Void
    init(_ handler: @escaping (Any?) -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler(sender) }
}

/// A flipped container, so scrolled content starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

enum UI {
    static func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.isSelectable = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return view
    }

    static func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    static func vertical(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func iconBadge(symbol: String, enabled: Bool, size: CGFloat = 26) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = size * 0.25
        container.layer?.backgroundColor = (enabled ? NSColor.controlAccentColor
                                                    : NSColor.tertiaryLabelColor).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size)
        ])

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView.contentTintColor = .white
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .medium)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    /// Wraps a vertical stack in a scrolling document view that fills the width.
    static func scrollable(_ stack: NSStackView, padding: CGFloat = 24) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }
}

// MARK: - Sidebar

final class SidebarRow: NSView {
    private let onSelect: () -> Void

    var isSelected: Bool = false {
        didSet { updateBackground() }
    }

    init(icon: String, title: String, subtitle: String?, enabled: Bool,
         showSwitch: Bool, onToggle: ((Bool) -> Void)?, onSelect: @escaping () -> Void,
         retained: inout [ActionProxy]) {
        self.onSelect = onSelect
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7

        let badge = UI.iconBadge(symbol: icon, enabled: enabled)

        let titleLabel = UI.label(title, font: .systemFont(ofSize: 13, weight: .medium))
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        var textViews: [NSView] = [titleLabel]
        if let subtitle = subtitle {
            let subtitleLabel = UI.label(subtitle, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.maximumNumberOfLines = 1
            textViews.append(subtitleLabel)
        }
        let texts = UI.vertical(textViews, spacing: 0)

        var views: [NSView] = [badge, texts, UI.spacer()]
        if showSwitch {
            let toggle = NSSwitch()
            toggle.state = enabled ? .on : .off
            toggle.controlSize = .small
            let proxy = ActionProxy { [weak toggle] _ in
                onToggle?(toggle?.state == .on)
            }
            retained.append(proxy)
            toggle.target = proxy
            toggle.action = #selector(ActionProxy.fire(_:))
            views.append(toggle)
        }

        let row = UI.horizontal(views, spacing: 9)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func mouseDown(with event: NSEvent) { onSelect() }

    private func updateBackground() {
        layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor
    }
}

final class SidebarViewController: NSViewController {
    private let model: AppModel
    var onSelect: ((String) -> Void)?

    private let stack = NSStackView()
    private var retained: [ActionProxy] = []

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        let root = NSView()

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        scroll.documentView = container
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        ])

        view = root
        reload()
    }

    func reload() {
        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        retained.removeAll()

        stack.addArrangedSubview(sectionHeader("AUGMENTS"))

        for augment in model.augments {
            let row = SidebarRow(
                icon: augment.icon,
                title: augment.name,
                subtitle: augment.tagline,
                enabled: augment.enabled,
                showSwitch: true,
                onToggle: { [weak self] value in
                    self?.model.setEnabled(augment, value)
                    self?.reload()
                    self?.onSelect?(augment.id)
                },
                onSelect: { [weak self] in self?.onSelect?(augment.id) },
                retained: &retained
            )
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            row.isSelected = (augment.id == model.selection)
        }

        stack.addArrangedSubview(sectionHeader("APP"))

        let general = SidebarRow(
            icon: "gearshape.fill", title: "General", subtitle: "Startup and housekeeping",
            enabled: true, showSwitch: false, onToggle: nil,
            onSelect: { [weak self] in self?.onSelect?("general") },
            retained: &retained
        )
        stack.addArrangedSubview(general)
        general.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        general.isSelected = (model.selection == "general")
    }

    private func sectionHeader(_ text: String) -> NSView {
        let label = UI.label(text, font: .systemFont(ofSize: 10, weight: .semibold), color: .tertiaryLabelColor)
        let container = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }
}

// MARK: - Detail

final class DetailViewController: NSViewController {
    private let model: AppModel
    private let content = NSStackView()
    private var retained: [ActionProxy] = []

    private var statusUpdater: (() -> Void)?
    private var timer: Timer?
    private var currentID: String?

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18

        let scroll = UI.scrollable(content)
        let root = NSView()
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        view = root

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.statusUpdater?()
        }
    }

    /// Rebuilds the current page, used when a setting changes what's on it.
    func rebuild() {
        if let id = currentID { show(id: id) }
    }

    func show(id: String) {
        currentID = id
        for subview in content.arrangedSubviews {
            content.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        retained.removeAll()
        statusUpdater = nil

        if id == "general" {
            buildGeneral()
        } else if let augment = model.augments.first(where: { $0.id == id }) {
            build(augment: augment)
        } else {
            let placeholder = UI.label("Select an augment", font: .systemFont(ofSize: 15), color: .secondaryLabelColor)
            content.addArrangedSubview(placeholder)
        }
    }

    // MARK: Augment page

    private func build(augment: Augment) {
        // Header
        let badge = UI.iconBadge(symbol: augment.icon, enabled: augment.enabled, size: 46)
        let name = UI.label(augment.name, font: .systemFont(ofSize: 22, weight: .bold))
        let tagline = UI.label(augment.tagline, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let titles = UI.vertical([name, tagline], spacing: 2)

        let toggle = NSSwitch()
        toggle.state = augment.enabled ? .on : .off
        let toggleProxy = ActionProxy { [weak self] sender in
            let on = (sender as? NSSwitch)?.state == .on
            self?.model.setEnabled(augment, on)
            // The augment may add or remove UI (a menu bar item), so redraw.
            DispatchQueue.main.async { self?.rebuild() }
        }
        retained.append(toggleProxy)
        toggle.target = toggleProxy
        toggle.action = #selector(ActionProxy.fire(_:))

        let header = UI.horizontal([badge, titles, UI.spacer(), toggle], spacing: 14)
        add(header, fullWidth: true)

        add(UI.label(augment.description, font: .systemFont(ofSize: 13), color: .secondaryLabelColor), fullWidth: true, top: 6)

        // Requirements
        if !augment.requirements.isEmpty {
            add(sectionTitle("Before you start"), fullWidth: true, top: 6)
            for requirement in augment.requirements {
                add(requirementRow(requirement), fullWidth: true)
            }
        }

        // Settings, grouped
        var seen: [String] = []
        for spec in augment.visibleSpecs where !seen.contains(spec.group) { seen.append(spec.group) }

        for group in seen {
            add(sectionTitle(group), fullWidth: true, top: 6)
            for spec in augment.visibleSpecs where spec.group == group {
                add(settingRow(spec, augment: augment), fullWidth: true)
            }
        }

        // Status
        add(sectionTitle("Status"), fullWidth: true, top: 6)
        let statusLabel = UI.label(augment.status, font: .systemFont(ofSize: 12))
        let eventLabel = UI.label(augment.lastEvent ?? "No gesture yet", font: .systemFont(ofSize: 12),
                                  color: .secondaryLabelColor)
        let logLabel = UI.label(Log.url.path, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        add(infoRow("Status", statusLabel), fullWidth: true)
        if augment.lastEvent != nil {
            add(infoRow("Last gesture", eventLabel), fullWidth: true)
        }
        add(infoRow("Log", logLabel), fullWidth: true)

        statusUpdater = { [weak statusLabel, weak eventLabel] in
            statusLabel?.stringValue = augment.status
            eventLabel?.stringValue = augment.lastEvent ?? "No gesture yet"
        }
    }

    // MARK: General page

    private func buildGeneral() {
        add(UI.label("General", font: .systemFont(ofSize: 22, weight: .bold)), fullWidth: true)
        add(UI.label("App-wide settings and housekeeping.", font: .systemFont(ofSize: 13),
                     color: .secondaryLabelColor), fullWidth: true)

        if let message = model.message {
            add(UI.label(message, font: .systemFont(ofSize: 12), color: .systemOrange), fullWidth: true, top: 6)
        }

        add(sectionTitle("Startup"), fullWidth: true, top: 6)
        let loginToggle = NSSwitch()
        loginToggle.state = model.launchAtLogin ? .on : .off
        let proxy = ActionProxy { [weak self] sender in
            let on = (sender as? NSSwitch)?.state == .on
            self?.model.setLaunchAtLogin(on)
            self?.show(id: "general")
        }
        retained.append(proxy)
        loginToggle.target = proxy
        loginToggle.action = #selector(ActionProxy.fire(_:))
        let loginLabel = UI.label("Launch Improvements at login", font: .systemFont(ofSize: 13))
        add(UI.horizontal([loginLabel, UI.spacer(), loginToggle]), fullWidth: true)
        add(UI.label("Keeps your augments running without having to open the app.",
                     font: .systemFont(ofSize: 11), color: .secondaryLabelColor), fullWidth: true)

        let legacyFound = Legacy.all.filter { $0.isInstalled() }
        if !legacyFound.isEmpty {
            add(sectionTitle("Old versions found"), fullWidth: true, top: 6)
            for item in legacyFound {
                add(UI.label(item.detail, font: .systemFont(ofSize: 12), color: .secondaryLabelColor),
                    fullWidth: true)
                let removeButton = NSButton(title: item.buttonTitle, target: nil, action: nil)
                let removeProxy = ActionProxy { [weak self] _ in
                    item.remove()
                    self?.show(id: "general")
                }
                retained.append(removeProxy)
                removeButton.target = removeProxy
                removeButton.action = #selector(ActionProxy.fire(_:))
                add(removeButton, top: 4)
            }
        }

        add(sectionTitle("Files"), fullWidth: true, top: 6)
        add(infoRow("Augments on", UI.label("\(model.augments.filter { $0.enabled }.count) of \(model.augments.count)",
                                            font: .systemFont(ofSize: 12))), fullWidth: true)
        add(infoRow("Settings", UI.label(configPath, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)),
            fullWidth: true)

        let revealLog = NSButton(title: "Reveal log", target: nil, action: nil)
        let revealLogProxy = ActionProxy { _ in
            NSWorkspace.shared.activateFileViewerSelecting([Log.url])
        }
        retained.append(revealLogProxy)
        revealLog.target = revealLogProxy
        revealLog.action = #selector(ActionProxy.fire(_:))

        let revealConfig = NSButton(title: "Reveal settings", target: nil, action: nil)
        let revealConfigProxy = ActionProxy { _ in
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: self.configPath)])
        }
        retained.append(revealConfigProxy)
        revealConfig.target = revealConfigProxy
        revealConfig.action = #selector(ActionProxy.fire(_:))

        add(UI.horizontal([revealLog, revealConfig], spacing: 8), top: 4)

        add(UI.label("Improvements 1.0 · MIT licensed", font: .systemFont(ofSize: 11),
                     color: .tertiaryLabelColor), fullWidth: true, top: 10)
    }

    // MARK: Setting controls

    private func settingRow(_ spec: SettingSpec, augment: Augment) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4

        // Rows span the column. The width constraint is activated only after
        // the row is a subview of `column`, so the two share a hierarchy —
        // activating it before that throws inside AppKit.
        func addRow(_ view: NSView) {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }

        let title = UI.label(spec.label, font: .systemFont(ofSize: 13))

        switch spec.kind {
        case .toggle:
            let toggle = NSSwitch()
            toggle.state = augment.bool(spec.id) ? .on : .off
            let proxy = ActionProxy { [weak toggle] _ in
                augment.set(spec.id, .bool(toggle?.state == .on))
            }
            retained.append(proxy)
            toggle.target = proxy
            toggle.action = #selector(ActionProxy.fire(_:))
            addRow(UI.horizontal([title, UI.spacer(), toggle]))

        case .stepper(let range, let step):
            let valueLabel = UI.label("\(augment.int(spec.id))", font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                                      color: .secondaryLabelColor)
            valueLabel.alignment = .right
            let stepper = NSStepper()
            stepper.minValue = Double(range.lowerBound)
            stepper.maxValue = Double(range.upperBound)
            stepper.increment = Double(step)
            stepper.integerValue = augment.int(spec.id)
            let proxy = ActionProxy { [weak stepper, weak valueLabel] _ in
                guard let stepper = stepper else { return }
                augment.set(spec.id, .int(stepper.integerValue))
                valueLabel?.stringValue = "\(stepper.integerValue)"
            }
            retained.append(proxy)
            stepper.target = proxy
            stepper.action = #selector(ActionProxy.fire(_:))
            valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
            addRow(UI.horizontal([title, UI.spacer(), valueLabel, stepper]))

        case .slider(let range, let step, let format):
            let valueLabel = UI.label(String(format: format, augment.double(spec.id)),
                                      font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                                      color: .secondaryLabelColor)
            valueLabel.alignment = .right
            valueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let slider = NSSlider(value: augment.double(spec.id), minValue: range.lowerBound,
                                  maxValue: range.upperBound, target: nil, action: nil)
            slider.isContinuous = true
            let proxy = ActionProxy { [weak slider, weak valueLabel] _ in
                guard let slider = slider else { return }
                let raw = slider.doubleValue
                let snapped = (raw / step).rounded() * step
                augment.set(spec.id, .double(snapped))
                valueLabel?.stringValue = String(format: format, snapped)
            }
            retained.append(proxy)
            slider.target = proxy
            slider.action = #selector(ActionProxy.fire(_:))
            addRow(UI.horizontal([title, UI.spacer(), valueLabel]))
            addRow(slider)

        case .text(let placeholder):
            let field = NSTextField(string: augment.string(spec.id))
            field.placeholderString = placeholder
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            let proxy = ActionProxy { [weak field] _ in
                augment.set(spec.id, .string(field?.stringValue ?? ""))
            }
            retained.append(proxy)
            field.target = proxy
            field.action = #selector(ActionProxy.fire(_:))
            title.widthAnchor.constraint(equalToConstant: 150).isActive = true
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addRow(UI.horizontal([title, field]))

        case .shortcut(let placeholder):
            let field = NSTextField(string: augment.string(spec.id))
            field.placeholderString = placeholder
            field.translatesAutoresizingMaskIntoConstraints = false
            let proxy = ActionProxy { [weak field] _ in
                augment.set(spec.id, .string(field?.stringValue ?? ""))
            }
            retained.append(proxy)
            field.target = proxy
            field.action = #selector(ActionProxy.fire(_:))

            let test = NSButton(title: "Test", target: nil, action: nil)
            let testProxy = ActionProxy { [weak field] _ in
                guard let text = field?.stringValue, let combo = ShortcutParser.parse(text) else {
                    Log.write("test shortcut: could not parse \"\(field?.stringValue ?? "")\"")
                    return
                }
                Log.write("test shortcut \(combo.display) permission=\(ShortcutPoster.hasPermission)")
                _ = ShortcutPoster.post(combo)
            }
            retained.append(testProxy)
            test.target = testProxy
            test.action = #selector(ActionProxy.fire(_:))

            title.widthAnchor.constraint(equalToConstant: 150).isActive = true
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addRow(UI.horizontal([title, field, test]))

        case .choice(let options):
            let popup = NSPopUpButton()
            popup.addItems(withTitles: options)
            let current = augment.string(spec.id)
            if options.contains(current) { popup.selectItem(withTitle: current) }
            let proxy = ActionProxy { [weak self, weak popup] _ in
                augment.set(spec.id, .string(popup?.titleOfSelectedItem ?? ""))
                // A choice can change which settings (and requirements) apply,
                // so rebuild once the control has finished sending its action.
                DispatchQueue.main.async { self?.rebuild() }
            }
            retained.append(proxy)
            popup.target = proxy
            popup.action = #selector(ActionProxy.fire(_:))
            title.widthAnchor.constraint(equalToConstant: 150).isActive = true
            addRow(UI.horizontal([title, popup]))
        }

        if let help = spec.help {
            addRow(UI.label(help, font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        }

        return column
    }

    private func requirementRow(_ requirement: Requirement) -> NSView {
        let satisfied = requirement.isSatisfied()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: satisfied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             accessibilityDescription: nil)
        icon.contentTintColor = satisfied ? .systemGreen : .systemOrange

        let text = UI.label(requirement.text, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        var views: [NSView] = [icon, text, UI.spacer()]
        if !satisfied, let fixLabel = requirement.fixLabel, let fix = requirement.fix {
            let button = NSButton(title: fixLabel, target: nil, action: nil)
            let proxy = ActionProxy { [weak self] _ in
                fix()
                self?.show(id: self?.model.selection ?? "general")
            }
            retained.append(proxy)
            button.target = proxy
            button.action = #selector(ActionProxy.fire(_:))
            views.append(button)
        }
        return UI.horizontal(views, spacing: 8)
    }

    // MARK: Building blocks

    private func sectionTitle(_ text: String) -> NSView {
        UI.label(text, font: .systemFont(ofSize: 13, weight: .semibold))
    }

    private func infoRow(_ label: String, _ value: NSTextField) -> NSView {
        let title = UI.label(label, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        title.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return UI.horizontal([title, value, UI.spacer()], spacing: 10)
    }

    private func add(_ view: NSView, fullWidth: Bool = false, top: CGFloat = 0) {
        content.addArrangedSubview(view)
        if fullWidth {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let count = content.arrangedSubviews.count
        if top > 0, count >= 2 {
            content.setCustomSpacing(top, after: content.arrangedSubviews[count - 2])
        }
    }

    private var configPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Improvements/config.json").path
    }
}
