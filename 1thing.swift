import AppKit
import ServiceManagement
import QuartzCore

private enum AppInfo {
    static let name = "1thing"
    static let releaseName: String? = "Taarnet"
    static let description = "A lightweight menu bar app that keeps one thing visible at all times."
    static let author = "Copyright © 2026 Steffen Wöll"
    static let website = "https://steffenwoell.github.io"

    static var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.9"
    }

    static var displayVersion: String {
        guard let releaseName, !releaseName.isEmpty else {
            return "\(name) \(version)"
        }

        return "\(name) \(version) \"\(releaseName)\""
    }
}

private enum DefaultsKey {
    static let text = "menuBarText"
    static let colorMode = "textColorMode"
    static let brightProfileColor = "brightProfileColor"
    static let mixedProfileColor = "mixedProfileColor"
    static let darkProfileColor = "darkProfileColor"
    static let colorProfilesMigrated = "colorProfilesMigrated"
    static let characterLimit = "characterLimit"
    static let textStyle = "textStyle"

    // Legacy keys used only for the one-time 1.3 migration.
    static let legacyLightColor = "lightModeTextColor"
    static let legacyDarkColor = "darkModeTextColor"
}

private enum TextColorMode: String, CaseIterable {
    case automatic
    case bright
    case mixed
    case dark

    // Visual order in the editor. Automatic intentionally sits on the right.
    static let editorOrder: [TextColorMode] = [
        .bright,
        .mixed,
        .dark,
        .automatic
    ]

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .bright: return "Light"
        case .mixed: return "Mixed"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .automatic: return "arrow.triangle.2.circlepath"
        case .bright: return "sun.max.fill"
        case .mixed: return "circle.righthalf.filled"
        case .dark: return "moon.fill"
        }
    }

    var colorDefaultsKey: String? {
        switch self {
        case .automatic: return nil
        case .bright: return DefaultsKey.brightProfileColor
        case .mixed: return DefaultsKey.mixedProfileColor
        case .dark: return DefaultsKey.darkProfileColor
        }
    }
}
private enum TextStyle: String, CaseIterable {
    case normal
    case bold
    case italic

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .bold: return "Bold"
        case .italic: return "Italic"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: return "character"
        case .bold: return "bold"
        case .italic: return "italic"
        }
    }
}

final class HistoryStore {
    private let fileManager = FileManager.default

    private var historyURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("1thing", isDirectory: true)
            .appendingPathComponent("history.txt", isDirectory: false)
    }

    func load() -> [String] {
        guard let data = try? Data(contentsOf: historyURL),
              let contents = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return contents
            .split { $0.isNewline }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func record(_ entry: String) {
        guard !entry.isEmpty else {
            return
        }

        var entries = load()
        entries.removeAll { $0 == entry }
        entries.insert(entry, at: 0)

        let contents = entries.joined(separator: "\n") + "\n"
        let directoryURL = historyURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try contents.write(
                to: historyURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            let message = "1thing: Could not write history: \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    func openFile() {
        let directoryURL = historyURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            if !fileManager.fileExists(atPath: historyURL.path) {
                try "".write(
                    to: historyURL,
                    atomically: true,
                    encoding: .utf8
                )
            }

            NSWorkspace.shared.open(historyURL)
        } catch {
            let message = "1thing: Could not open history: \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }
}

private protocol SubtleHoverControl: AnyObject {
    var restAlpha: CGFloat { get set }
    var hoverAlpha: CGFloat { get }
}

private extension SubtleHoverControl where Self: NSControl {
    func animateHover(_ isHovered: Bool) {
        guard isEnabled else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = isHovered ? hoverAlpha : restAlpha
        }
    }
}

final class HoverSegmentedControl: NSSegmentedControl {
    private var trackingAreaReference: NSTrackingArea?
    private let hoverOverlay = CALayer()
    private var hoveredSegment = -1

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        alphaValue = 1.0
        installHoverOverlayIfNeeded()
        updateHoverOverlayColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverOverlayColor()
    }

    override func layout() {
        super.layout()
        updateHoverOverlayFrame(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .activeAlways,
                .mouseEnteredAndExited,
                .mouseMoved,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoveredSegment(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredSegment(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredSegment(-1)
    }

    private func installHoverOverlayIfNeeded() {
        wantsLayer = true
        guard hoverOverlay.superlayer == nil, let layer else { return }

        updateHoverOverlayColor()
        hoverOverlay.cornerRadius = 6
        hoverOverlay.opacity = 0
        layer.addSublayer(hoverOverlay)
    }

    private func updateHoverOverlayColor() {
        let appearance = effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]
        )
        let alpha: CGFloat = appearance == .aqua ? 0.13 : 0.08

        hoverOverlay.backgroundColor = NSColor.labelColor
            .withAlphaComponent(alpha)
            .cgColor
    }

    private func updateHoveredSegment(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHoveredSegment(segmentIndex(at: point))
    }

    private func segmentIndex(at point: NSPoint) -> Int {
        guard bounds.contains(point), segmentCount > 0 else { return -1 }

        // Both profile and format controls use equal-width segments.
        let width = bounds.width / CGFloat(segmentCount)
        guard width > 0 else { return -1 }

        return min(
            segmentCount - 1,
            max(0, Int(point.x / width))
        )
    }

    private func setHoveredSegment(_ index: Int) {
        guard index != hoveredSegment else { return }
        hoveredSegment = index
        updateHoverOverlayFrame(animated: true)
    }

    private func segmentRect(for index: Int) -> NSRect {
        let count = max(segmentCount, 1)
        let width = bounds.width / CGFloat(count)

        return NSRect(
            x: CGFloat(index) * width,
            y: 0,
            width: width,
            height: bounds.height
        )
    }

    private func updateHoverOverlayFrame(animated: Bool) {
        installHoverOverlayIfNeeded()

        let visible = hoveredSegment >= 0 && hoveredSegment < segmentCount
        let targetFrame = visible
            ? segmentRect(for: hoveredSegment).insetBy(dx: 1.5, dy: 1.5)
            : hoverOverlay.frame

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.24 : 0)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )
        hoverOverlay.frame = targetFrame
        hoverOverlay.opacity = visible ? 1 : 0
        CATransaction.commit()
    }
}

final class HoverColorWell: NSColorWell, SubtleHoverControl {
    var restAlpha: CGFloat = 0.35 {
        didSet {
            if !isHovered { alphaValue = restAlpha }
        }
    }
    let hoverAlpha: CGFloat = 1.0
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        animateHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        animateHover(false)
    }
}

final class HoverStepper: NSStepper, SubtleHoverControl {
    var restAlpha: CGFloat = 0.9
    let hoverAlpha: CGFloat = 1.0
    private var trackingAreaReference: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        alphaValue = restAlpha
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) { animateHover(true) }
    override func mouseExited(with event: NSEvent) { animateHover(false) }
}

final class HoverIconButton: NSButton {
    private var trackingAreaReference: NSTrackingArea?

    init(
        systemSymbolName: String,
        accessibilityDescription: String
    ) {
        super.init(frame: .zero)
        configure(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func configure(
        systemSymbolName: String,
        accessibilityDescription: String
    ) {
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = .labelColor
        alphaValue = 0.72
        wantsLayer = true

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .medium
        )
        image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(configuration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        animateHover(isHovered: true)
    }

    override func mouseExited(with event: NSEvent) {
        animateHover(isHovered: false)
    }

    private func animateHover(isHovered: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            animator().alphaValue = isHovered ? 1.0 : 0.72
        }
    }
}



final class EditorViewController: NSViewController {
    let textField = NSTextField()
    let historyButton = HoverIconButton(
        systemSymbolName: "clock.arrow.circlepath",
        accessibilityDescription: "Show recent entries"
    )
    let clearButton = HoverIconButton(
        systemSymbolName: "xmark.circle.fill",
        accessibilityDescription: "Clear text"
    )
    let colorProfileControl = HoverSegmentedControl()
    let textStyleControl = HoverSegmentedControl()
    let characterLimitField = NSTextField()
    let characterLimitStepper = HoverStepper()

    let brightColorWell = HoverColorWell()
    let mixedColorWell = HoverColorWell()
    let darkColorWell = HoverColorWell()

    var profileColorWells: [HoverColorWell] {
        [brightColorWell, mixedColorWell, darkColorWell]
    }

    override func loadView() {
        // Give the popover content view a stable frame from the outset.
        // The root view itself is managed by NSPopover and must not participate
        // as an Auto Layout child; setting translatesAutoresizingMaskIntoConstraints
        // to false here allowed AppKit to recompute its fitting width after a
        // segmented-control selection changed.
        let root = NSView(
            frame: NSRect(x: 0, y: 0, width: 312, height: 153)
        )
        view = root

        textField.placeholderString = "What is the one thing? (↑)"
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.focusRingType = .none
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true

        characterLimitField.focusRingType = .none
        characterLimitField.isBordered = true
        characterLimitField.isBezeled = true
        characterLimitField.bezelStyle = .roundedBezel
        characterLimitField.drawsBackground = true
        characterLimitField.alignment = .right
        characterLimitField.controlSize = .small
        characterLimitField.font = NSFont.monospacedDigitSystemFont(
            ofSize: 12,
            weight: .regular
        )

        characterLimitField.textColor = .labelColor
        characterLimitStepper.minValue = 1
        characterLimitStepper.maxValue = 150
        characterLimitStepper.increment = 10
        characterLimitStepper.controlSize = .small

        historyButton.translatesAutoresizingMaskIntoConstraints = false
        historyButton.isHidden = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true

        let inputButtons = NSStackView(views: [historyButton, clearButton])
        inputButtons.orientation = .horizontal
        inputButtons.alignment = .centerY
        inputButtons.spacing = 2
        inputButtons.translatesAutoresizingMaskIntoConstraints = false

        let inputContainer = NSView()
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(textField)
        inputContainer.addSubview(inputButtons)
        textField.translatesAutoresizingMaskIntoConstraints = false

        configureColorProfileControl()
        configureTextStyleControl()

        let swatchRow = makeProfileSwatchRow()

        let characterIcon = NSImageView()
        characterIcon.translatesAutoresizingMaskIntoConstraints = false
        characterIcon.image = NSImage(
            systemSymbolName: "character.cursor.ibeam",
            accessibilityDescription: "Character limit"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
        characterIcon.contentTintColor = .secondaryLabelColor

        let characterControls = NSStackView(
            views: [characterIcon, characterLimitField, characterLimitStepper]
        )
        characterControls.orientation = .horizontal
        characterControls.alignment = .centerY
        characterControls.distribution = .fill
        characterControls.spacing = 4
        characterControls.translatesAutoresizingMaskIntoConstraints = false
        characterControls.setContentHuggingPriority(.required, for: .horizontal)
        characterControls.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        characterLimitField.setContentHuggingPriority(.required, for: .horizontal)
        characterLimitField.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        characterLimitStepper.setContentHuggingPriority(.required, for: .horizontal)
        characterLimitStepper.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        let bottomRow = NSStackView(
            views: [textStyleControl, characterControls]
        )
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fill
        bottomRow.spacing = 10
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        textStyleControl.setContentHuggingPriority(.required, for: .horizontal)
        textStyleControl.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        colorProfileControl.translatesAutoresizingMaskIntoConstraints = false
        swatchRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(inputContainer)
        root.addSubview(colorProfileControl)
        root.addSubview(swatchRow)
        root.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 14
            ),
            inputContainer.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -14
            ),
            inputContainer.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: 14
            ),
            inputContainer.heightAnchor.constraint(equalToConstant: 28),

            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            textField.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            textField.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),

            inputButtons.trailingAnchor.constraint(
                equalTo: inputContainer.trailingAnchor,
                constant: -5
            ),
            inputButtons.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            historyButton.widthAnchor.constraint(equalToConstant: 18),
            historyButton.heightAnchor.constraint(equalToConstant: 18),
            clearButton.widthAnchor.constraint(equalToConstant: 18),
            clearButton.heightAnchor.constraint(equalToConstant: 18),

            colorProfileControl.leadingAnchor.constraint(
                equalTo: inputContainer.leadingAnchor
            ),
            colorProfileControl.trailingAnchor.constraint(
                equalTo: inputContainer.trailingAnchor
            ),
            colorProfileControl.topAnchor.constraint(
                equalTo: inputContainer.bottomAnchor,
                constant: 12
            ),

            swatchRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            swatchRow.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            swatchRow.topAnchor.constraint(
                equalTo: colorProfileControl.bottomAnchor,
                constant: 0
            ),

            bottomRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            bottomRow.topAnchor.constraint(
                equalTo: swatchRow.bottomAnchor,
                constant: 10
            ),
            bottomRow.bottomAnchor.constraint(
                equalTo: root.bottomAnchor,
                constant: -9
            ),

            characterIcon.widthAnchor.constraint(equalToConstant: 18),
            characterIcon.heightAnchor.constraint(equalToConstant: 18),
            characterLimitField.widthAnchor.constraint(equalToConstant: 44),
            characterLimitField.heightAnchor.constraint(equalToConstant: 22),
            textStyleControl.widthAnchor.constraint(equalToConstant: 124)
        ])
    }

    private func configureColorProfileControl() {
        colorProfileControl.segmentCount = TextColorMode.editorOrder.count
        colorProfileControl.trackingMode = .selectOne
        colorProfileControl.controlSize = .regular

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .regular
        )

        for (index, mode) in TextColorMode.editorOrder.enumerated() {
            let image = NSImage(
                systemSymbolName: mode.symbolName,
                accessibilityDescription: mode.title
            )?.withSymbolConfiguration(configuration)

            colorProfileControl.setImage(image, forSegment: index)
            colorProfileControl.setLabel("", forSegment: index)
        }
    }

    private func makeProfileSwatchRow() -> NSStackView {
        let automaticSlot = NSView()
        automaticSlot.translatesAutoresizingMaskIntoConstraints = false

        let wellSlots: [NSView] = profileColorWells.map { well in
            well.translatesAutoresizingMaskIntoConstraints = false
            well.controlSize = .small

            let slot = NSView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.addSubview(well)

            NSLayoutConstraint.activate([
                well.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
                well.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
                well.topAnchor.constraint(equalTo: slot.topAnchor),
                well.bottomAnchor.constraint(equalTo: slot.bottomAnchor)
            ])

            return slot
        }

        // Mirrors TextColorMode.editorOrder: Light, Mixed, Dark, Automatic.
        let row = NSStackView(views: wellSlots + [automaticSlot])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 16.4).isActive = true

        return row
    }

    private func configureTextStyleControl() {
        textStyleControl.segmentCount = TextStyle.allCases.count
        textStyleControl.trackingMode = .selectOne
        textStyleControl.controlSize = .regular

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .regular
        )

        for (index, style) in TextStyle.allCases.enumerated() {
            let image = NSImage(
                systemSymbolName: style.symbolName,
                accessibilityDescription: style.title
            )?.withSymbolConfiguration(configuration)

            textStyleControl.setImage(image, forSegment: index)
            textStyleControl.setLabel("", forSegment: index)
            textStyleControl.setWidth(40, forSegment: index)
        }
    }
}

final class AppDelegate: NSObject,
    NSApplicationDelegate,
    NSTextFieldDelegate
{
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let editor = EditorViewController()

    private let defaults = UserDefaults.standard
    private let historyStore = HistoryStore()

    private let popoverWidth: CGFloat = 312
    private let popoverHeight: CGFloat = 153

    private var historyEntries: [String] = []
    private var historyIndex: Int?
    private var historyDraft = ""
    private var isApplyingHistoryEntry = false

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaults()
        migrateColorProfilesIfNeeded()
        createMainMenu()
        createStatusItem()
        createPopover()
        configureEditorActions()
        updateStatusItem()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            DefaultsKey.text: "1thing",
            DefaultsKey.colorMode: TextColorMode.automatic.rawValue,
            DefaultsKey.brightProfileColor: "#000000",
            DefaultsKey.mixedProfileColor: "#7A26C1",
            DefaultsKey.darkProfileColor: "#FFFFFF",
            DefaultsKey.characterLimit: 40,
            DefaultsKey.textStyle: TextStyle.normal.rawValue
        ])
    }

    private func migrateColorProfilesIfNeeded() {
        guard !defaults.bool(forKey: DefaultsKey.colorProfilesMigrated) else {
            return
        }

        let legacyLight = defaults.string(
            forKey: DefaultsKey.legacyLightColor
        ) ?? "#000000"
        let legacyDark = defaults.string(
            forKey: DefaultsKey.legacyDarkColor
        ) ?? "#FFFFFF"
        let legacyMode = defaults.string(forKey: DefaultsKey.colorMode)

        defaults.set(legacyLight, forKey: DefaultsKey.brightProfileColor)
        defaults.set(legacyLight, forKey: DefaultsKey.mixedProfileColor)
        defaults.set(legacyDark, forKey: DefaultsKey.darkProfileColor)

        if legacyMode == "custom" {
            defaults.set(
                isDarkMode
                    ? TextColorMode.dark.rawValue
                    : TextColorMode.bright.rawValue,
                forKey: DefaultsKey.colorMode
            )
        } else if TextColorMode(rawValue: legacyMode ?? "") == nil {
            defaults.set(
                TextColorMode.automatic.rawValue,
                forKey: DefaultsKey.colorMode
            )
        }

        defaults.set(true, forKey: DefaultsKey.colorProfilesMigrated)
    }

    // MARK: - Main menu

    private func createMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(
            title: AppInfo.name,
            action: nil,
            keyEquivalent: ""
        )
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: AppInfo.name)

        let aboutItem = NSMenuItem(
            title: "About \(AppInfo.name)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem(
            title: "Edit",
            action: nil,
            keyEquivalent: ""
        )
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenuItem.submenu = editMenu

        let profileMenuItem = NSMenuItem(
            title: "Profile",
            action: nil,
            keyEquivalent: ""
        )
        mainMenu.addItem(profileMenuItem)

        let profileMenu = NSMenu(title: "Profile")
        for (index, mode) in TextColorMode.editorOrder.enumerated() {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectProfileShortcut(_:)),
                keyEquivalent: String(index + 1)
            )
            item.target = self
            item.representedObject = mode.rawValue
            profileMenu.addItem(item)
        }
        profileMenuItem.submenu = profileMenu

        let formatMenuItem = NSMenuItem(
            title: "Format",
            action: nil,
            keyEquivalent: ""
        )
        mainMenu.addItem(formatMenuItem)

        let formatMenu = NSMenu(title: "Format")
        let boldItem = NSMenuItem(
            title: "Bold",
            action: #selector(toggleBoldShortcut),
            keyEquivalent: "b"
        )
        boldItem.target = self
        formatMenu.addItem(boldItem)

        let italicItem = NSMenuItem(
            title: "Italic",
            action: #selector(toggleItalicShortcut),
            keyEquivalent: "i"
        )
        italicItem.target = self
        formatMenu.addItem(italicItem)
        formatMenuItem.submenu = formatMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let text = savedText()

        if text.isEmpty {
            showStatusIcon(on: button)
        } else {
            showStatusText(text, on: button)
        }

    }

    private func showStatusIcon(on button: NSStatusBarButton) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .medium
        )

        guard let symbol = NSImage(
            systemSymbolName: "1.circle.fill",
            accessibilityDescription: AppInfo.name
        )?.withSymbolConfiguration(configuration) else {
            return
        }

        let canvasSize = NSSize(width: 20, height: 20)
        let symbolSize = NSSize(width: 19, height: 19)

        let image = NSImage(size: canvasSize, flipped: false) { _ in
            let rect = NSRect(
                x: (canvasSize.width - symbolSize.width) / 2,
                y: (canvasSize.height - symbolSize.height) / 2 + 1,
                width: symbolSize.width,
                height: symbolSize.height
            )

            symbol.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            return true
        }

        image.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = nil
        statusItem.length = NSStatusItem.squareLength
    }

    private func showStatusText(
        _ text: String,
        on button: NSStatusBarButton
    ) {
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = nil

        var attributes: [NSAttributedString.Key: Any] = [
            .font: menuBarFont(),
            .foregroundColor: NSColor.labelColor,
            .baselineOffset: -1.5
        ]

        attributes[.foregroundColor] = currentProfileTextColor()

        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: attributes
        )

        // Keep the status item width stable while switching text styles.
        // Otherwise the popover moves because it is anchored to the status item.
        statusItem.length = stableStatusItemWidth(for: text)
    }

    private func stableStatusItemWidth(for text: String) -> CGFloat {
        let normalFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let fonts: [NSFont] = [
            normalFont,
            NSFont.systemFont(ofSize: 14, weight: .bold),
            NSFontManager.shared.convert(
                normalFont,
                toHaveTrait: .italicFontMask
            )
        ]

        let widestText = fonts
            .map { font in
                (text as NSString).size(
                    withAttributes: [.font: font]
                ).width
            }
            .max() ?? 0

        // Native status-bar buttons add horizontal internal padding.
        return ceil(widestText + 8)
    }

    @objc
    private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent,
              let button = statusItem.button
        else {
            return
        }

        if event.type == .rightMouseUp {
            showColorProfileMenu(for: button, event: event)
            return
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.shift) {
            clearTextImmediately()
            return
        }

        openPopoverReliably()
    }

    private func openPopoverReliably() {
        let wasActive = NSApp.isActive
        NSApp.activate(ignoringOtherApps: true)

        if wasActive {
            togglePopover()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover()
            }
        }
    }

    private func showColorProfileMenu(
        for button: NSStatusBarButton,
        event: NSEvent
    ) {
        let menu = NSMenu()
        menu.appearance = systemMenuAppearance()

        let currentMode = textColorMode()

        for (index, mode) in TextColorMode.editorOrder.enumerated() {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectColorProfile(_:)),
                keyEquivalent: String(index + 1)
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == currentMode ? .on : .off
            item.image = menuImage(
                systemSymbolName: mode.symbolName,
                accessibilityDescription: mode.title
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLoginFromMenu),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let editItem = NSMenuItem(
            title: "Edit…",
            action: #selector(openEditorFromMenu),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        let clearItem = NSMenuItem(
            title: "Clear",
            action: #selector(clearTextFromMenu),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = !savedText().isEmpty
        menu.addItem(clearItem)

        let aboutItem = NSMenuItem(
            title: "About \(AppInfo.name)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private func systemMenuAppearance() -> NSAppearance? {
        let isDarkMode = UserDefaults.standard
            .string(forKey: "AppleInterfaceStyle") == "Dark"

        return NSAppearance(
            named: isDarkMode ? .darkAqua : .aqua
        )
    }

    private func menuImage(
        systemSymbolName: String,
        accessibilityDescription: String
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .regular
        )

        return NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(configuration)
    }

    @objc
    private func selectColorProfile(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = TextColorMode(rawValue: rawValue)
        else {
            return
        }

        setTextColorMode(mode)
    }

    @objc
    private func selectProfileShortcut(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = TextColorMode(rawValue: rawValue)
        else {
            return
        }

        setTextColorMode(mode)
    }

    @objc
    private func toggleBoldShortcut() {
        toggleTextStyle(.bold)
    }

    @objc
    private func toggleItalicShortcut() {
        toggleTextStyle(.italic)
    }

    @objc
    private func openEditorFromMenu() {
        if popover.isShown {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.togglePopover()
        }
    }

    @objc
    private func clearTextFromMenu() {
        clearTextImmediately()
    }

    // MARK: - Popover

    private func createPopover() {
        editor.loadView()
        editor.preferredContentSize = NSSize(
            width: popoverWidth,
            height: popoverHeight
        )

        popover.contentViewController = editor
        popover.contentSize = NSSize(
            width: popoverWidth,
            height: popoverHeight
        )
        popover.behavior = .transient
        popover.animates = true
    }

    private func configureEditorActions() {
        editor.textField.delegate = self
        editor.textField.target = self
        editor.textField.action = #selector(saveText)

        editor.historyButton.target = self
        editor.historyButton.action = #selector(showHistoryMenu)

        editor.clearButton.target = self
        editor.clearButton.action = #selector(clearEditorText)

        editor.colorProfileControl.target = self
        editor.colorProfileControl.action = #selector(colorModeChanged)

        editor.textStyleControl.target = self
        editor.textStyleControl.action = #selector(textStyleChanged)

        for colorWell in editor.profileColorWells {
            colorWell.target = self
            colorWell.action = #selector(profileColorChanged(_:))
        }

        editor.characterLimitField.delegate = self
        editor.characterLimitField.target = self
        editor.characterLimitField.action = #selector(characterLimitChanged)

        editor.characterLimitStepper.target = self
        editor.characterLimitStepper.action = #selector(characterLimitStepperChanged)

    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else {
            return
        }

        refreshEditor()

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.editor.view.window?.makeFirstResponder(
                self.editor.textField
            )
            self.editor.textField.selectText(nil)
        }
    }

    private func refreshEditor() {
        editor.textField.stringValue = savedText()
        resetHistoryNavigation()
        editor.characterLimitField.integerValue = characterLimit()
        editor.characterLimitStepper.integerValue = characterLimit()
        let mode = textColorMode()
        editor.colorProfileControl.selectedSegment =
            TextColorMode.editorOrder.firstIndex(of: mode) ?? 0
        refreshProfileColorWells()
        refreshTextStyleControl()
        editor.textField.font = NSFont.systemFont(ofSize: 14)
        updateColorControlsVisibility()
        updateInputButtonVisibility()
    }

    // MARK: - Text editing

    private func savedText() -> String {
        defaults.string(forKey: DefaultsKey.text) ?? ""
    }

    private func characterLimit() -> Int {
        min(
            200,
            max(1, defaults.integer(forKey: DefaultsKey.characterLimit))
        )
    }

    private func normalizedText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return String(trimmed.prefix(characterLimit()))
    }


    private func resetHistoryNavigation() {
        historyEntries = historyStore.load()
        historyIndex = nil
        historyDraft = editor.textField.stringValue
    }

    private func showPreviousHistoryEntry() {
        guard !historyEntries.isEmpty else {
            return
        }

        if historyIndex == nil {
            historyDraft = editor.textField.stringValue
            historyIndex = 0
        } else if let index = historyIndex,
                  index < historyEntries.count - 1 {
            historyIndex = index + 1
        }

        applyHistoryEntry()
    }

    private func showNextHistoryEntry() {
        guard let index = historyIndex else {
            return
        }

        if index > 0 {
            historyIndex = index - 1
            applyHistoryEntry()
        } else {
            historyIndex = nil
            setEditorText(historyDraft)
        }
    }

    private func applyHistoryEntry() {
        guard let index = historyIndex,
              historyEntries.indices.contains(index)
        else {
            return
        }

        setEditorText(historyEntries[index])
    }

    private func setEditorText(_ value: String) {
        let limitedValue = String(value.prefix(characterLimit()))

        isApplyingHistoryEntry = true
        editor.textField.stringValue = limitedValue
        isApplyingHistoryEntry = false
        updateInputButtonVisibility()
        editor.textField.currentEditor()?.selectedRange = NSRange(
            location: limitedValue.utf16.count,
            length: 0
        )
    }

    private func updateInputButtonVisibility() {
        editor.clearButton.isHidden = editor.textField.stringValue.isEmpty
        editor.historyButton.isHidden = historyEntries.isEmpty
    }

    private func trimEditorTextToLimit() {
        let limit = characterLimit()

        if editor.textField.stringValue.count > limit {
            editor.textField.stringValue = String(
                editor.textField.stringValue.prefix(limit)
            )
        }

        updateInputButtonVisibility()

        let saved = savedText()
        if saved.count > limit {
            let shortened = String(saved.prefix(limit))
            defaults.set(shortened, forKey: DefaultsKey.text)
            updateStatusItem()
        }
    }

    private func clearTextImmediately() {
        defaults.set("", forKey: DefaultsKey.text)
        editor.textField.stringValue = ""
        updateInputButtonVisibility()
        updateStatusItem()
    }

    @objc
    private func showHistoryMenu() {
        let entries = Array(historyStore.load().prefix(10))
        guard !entries.isEmpty else {
            return
        }

        let menu = NSMenu(title: "Recent Entries")

        for entry in entries {
            let item = NSMenuItem(
                title: historyMenuTitle(for: entry),
                action: #selector(selectHistoryMenuEntry(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openHistoryItem = NSMenuItem(
            title: "Open History File…",
            action: #selector(openHistoryFile),
            keyEquivalent: ""
        )
        openHistoryItem.target = self
        menu.addItem(openHistoryItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(
                x: 0,
                y: editor.historyButton.bounds.maxY + 2
            ),
            in: editor.historyButton
        )
    }

    private func historyMenuTitle(for entry: String) -> String {
        let maximumLength = 60
        guard entry.count > maximumLength else {
            return entry
        }

        return String(entry.prefix(maximumLength - 1)) + "…"
    }

    @objc
    private func selectHistoryMenuEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? String else {
            return
        }

        setEditorText(entry)
        historyIndex = nil
        historyDraft = editor.textField.stringValue
        editor.view.window?.makeFirstResponder(editor.textField)
    }

    @objc
    private func openHistoryFile() {
        historyStore.openFile()
    }

    @objc
    private func clearEditorText() {
        editor.textField.stringValue = ""
        updateInputButtonVisibility()
        editor.view.window?.makeFirstResponder(editor.textField)
    }

    @objc
    private func saveText() {
        let value = normalizedText(editor.textField.stringValue)
        defaults.set(value, forKey: DefaultsKey.text)
        editor.textField.stringValue = value
        historyStore.record(value)
        resetHistoryNavigation()

        updateStatusItem()
        popover.performClose(nil)
    }

    private func cancelEditing() {
        popover.performClose(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === editor.textField
        else {
            return
        }

        updateInputButtonVisibility()

        if !isApplyingHistoryEntry {
            historyIndex = nil
            historyDraft = field.stringValue
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        shouldChangeCharactersIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        let current = textView.string as NSString
        let replacement = replacementString ?? ""
        let updated = current.replacingCharacters(
            in: affectedCharRange,
            with: replacement
        )

        if control === editor.textField {
            return updated.count <= characterLimit()
        }

        if control === editor.characterLimitField {
            if updated.isEmpty {
                return true
            }

            return updated.count <= 3 &&
                updated.allSatisfy { $0.isNumber }
        }

        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === editor.characterLimitField
        else {
            return
        }

        applyCharacterLimitFieldValue()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            showPreviousHistoryEntry()
            return true
        }

        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            showNextHistoryEntry()
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            saveText()
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }

        return false
    }

    // MARK: - Character limit

    @objc
    private func characterLimitChanged() {
        applyCharacterLimitFieldValue()
    }

    private func applyCharacterLimitFieldValue() {
        let enteredValue = Int(
            editor.characterLimitField.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let value = min(150, max(1, enteredValue ?? characterLimit()))

        defaults.set(value, forKey: DefaultsKey.characterLimit)
        editor.characterLimitField.integerValue = value
        editor.characterLimitStepper.integerValue = value
        trimEditorTextToLimit()
    }

    @objc
    private func characterLimitStepperChanged() {
        let value = editor.characterLimitStepper.integerValue
        defaults.set(value, forKey: DefaultsKey.characterLimit)
        editor.characterLimitField.integerValue = value
        trimEditorTextToLimit()
    }

    // MARK: - Text style

    private func textStyle() -> TextStyle {
        let rawValue = defaults.string(
            forKey: DefaultsKey.textStyle
        ) ?? TextStyle.normal.rawValue

        return TextStyle(rawValue: rawValue) ?? .normal
    }

    private func menuBarFont() -> NSFont {
        let normalFont = NSFont.systemFont(
            ofSize: 14,
            weight: .semibold
        )

        switch textStyle() {
        case .normal:
            return normalFont
        case .bold:
            return NSFont.systemFont(ofSize: 14, weight: .bold)
        case .italic:
            return NSFontManager.shared.convert(
                normalFont,
                toHaveTrait: .italicFontMask
            )
        }
    }

    private func refreshTextStyleControl() {
        let style = textStyle()
        editor.textStyleControl.selectedSegment =
            TextStyle.allCases.firstIndex(of: style) ?? 0
    }

    private func toggleTextStyle(_ style: TextStyle) {
        let newStyle: TextStyle = textStyle() == style ? .normal : style
        defaults.set(newStyle.rawValue, forKey: DefaultsKey.textStyle)
        refreshTextStyleControl()
        editor.textField.font = NSFont.systemFont(ofSize: 14)
        updateStatusItem()
    }

    @objc
    private func textStyleChanged() {
        let index = editor.textStyleControl.selectedSegment
        guard TextStyle.allCases.indices.contains(index) else {
            return
        }

        let style = TextStyle.allCases[index]
        defaults.set(style.rawValue, forKey: DefaultsKey.textStyle)
        refreshTextStyleControl()
        editor.textField.font = NSFont.systemFont(ofSize: 14)
        updateStatusItem()
    }

    // MARK: - Appearance and colors

    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
    }

    private func textColorMode() -> TextColorMode {
        let rawValue = defaults.string(
            forKey: DefaultsKey.colorMode
        ) ?? TextColorMode.automatic.rawValue

        return TextColorMode(rawValue: rawValue) ?? .automatic
    }

    private func currentProfileTextColor() -> NSColor {
        let mode = textColorMode()

        if mode == .automatic {
            return colorForProfile(isDarkMode ? .dark : .bright)
        }

        return colorForProfile(mode)
    }

    private func colorForProfile(_ mode: TextColorMode) -> NSColor {
        guard let key = mode.colorDefaultsKey else {
            return .labelColor
        }

        switch mode {
        case .automatic:
            return .labelColor
        case .bright:
            return savedColor(forKey: key, fallback: .black)
        case .mixed:
            return savedColor(
                forKey: key,
                fallback: NSColor(
                    calibratedRed: 0.48,
                    green: 0.15,
                    blue: 0.76,
                    alpha: 1
                )
            )
        case .dark:
            return savedColor(forKey: key, fallback: .white)
        }
    }

    private func savedColor(
        forKey key: String,
        fallback: NSColor
    ) -> NSColor {
        guard let hex = defaults.string(forKey: key) else {
            return fallback
        }

        return color(fromHex: hex) ?? fallback
    }

    private func color(fromHex hex: String) -> NSColor? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16)
        else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        return NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }

    private func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return "#FFFFFF"
        }

        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))

        return String(
            format: "#%02X%02X%02X",
            red,
            green,
            blue
        )
    }

    private func refreshProfileColorWells() {
        let modes: [TextColorMode] = [.bright, .mixed, .dark]
        let selectedMode = textColorMode()

        for (mode, well) in zip(modes, editor.profileColorWells) {
            well.color = colorForProfile(mode)
            let isActive = selectedMode == mode
            well.isEnabled = true
            well.restAlpha = isActive ? 0.9 : 0.55
            well.alphaValue = well.restAlpha
        }
    }

    private func updateColorControlsVisibility() {
        // Only update the controls. Reapplying preferredContentSize/contentSize
        // while the popover is open makes AppKit run another fitting-size pass;
        // NSSegmentedControl can then contribute a selection-dependent intrinsic
        // width and visibly grow the popover to the right.
        refreshProfileColorWells()
    }

    private func setTextColorMode(_ mode: TextColorMode) {
        defaults.set(mode.rawValue, forKey: DefaultsKey.colorMode)

        if editor.isViewLoaded {
            editor.colorProfileControl.selectedSegment =
                TextColorMode.editorOrder.firstIndex(of: mode) ?? 0
            updateColorControlsVisibility()
        }

        updateStatusItem()
    }

    @objc
    private func colorModeChanged() {
        let index = editor.colorProfileControl.selectedSegment
        guard TextColorMode.editorOrder.indices.contains(index) else {
            return
        }

        setTextColorMode(TextColorMode.editorOrder[index])
    }

    @objc
    private func profileColorChanged(_ sender: NSColorWell) {
        let modes: [TextColorMode] = [.bright, .mixed, .dark]

        guard let index = editor.profileColorWells.firstIndex(where: { $0 === sender }),
              modes.indices.contains(index),
              let key = modes[index].colorDefaultsKey
        else {
            return
        }

        defaults.set(
            hexString(from: sender.color),
            forKey: key
        )
        updateStatusItem()
    }

    @objc
    private func appearanceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
        }
    }

    // MARK: - Launch at login

    @objc
    private func toggleLaunchAtLoginFromMenu() {
        let service = SMAppService.mainApp

        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSSound.beep()

            let alert = NSAlert()
            alert.messageText = "Could not update launch at login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - About

    @objc
    private func showAbout() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = AppInfo.displayVersion
        alert.informativeText = AppInfo.description

        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 330, height: 82)
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.alignment = .center
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let text = NSMutableAttributedString(
            string: "\(AppInfo.author)\n",
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: NSFont.systemFontSize
                ),
                .foregroundColor: NSColor.labelColor
            ]
        )

        if let websiteURL = URL(string: AppInfo.website) {
            let website = NSAttributedString(
                string: "steffenwoell.github.io",
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: NSFont.systemFontSize
                    ),
                    .link: websiteURL,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            )
            text.append(website)
        }

        text.append(
            NSAttributedString(
                string: "\n\nLicensed under the MIT License",
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: NSFont.systemFontSize
                    ),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        text.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: text.length)
        )
        textView.textStorage?.setAttributedString(text)

        alert.accessoryView = textView
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - General actions

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
