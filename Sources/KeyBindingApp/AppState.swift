import AppKit
import Carbon
import Combine
import os
import Foundation

/// The key monitor's last press: what the keyboard sent and what macOS made of it.
struct KeyLogEntry: Identifiable, Equatable {
    let id = UUID()
    var hid: HIDKeyEvent?
    var macKeyCode: UInt16?
    var characters: String?
    var macModifiers: ModifierSet = []
    let time: Date

    /// True when the keyboard sent the key but no macOS key event followed.
    var macIgnoredIt: Bool { hid != nil && macKeyCode == nil && Date().timeIntervalSince(time) > 0.4 }
}

/// The app's single source of truth: saved config, live keyboard state and the engines.
final class AppState: NSObject, ObservableObject {
    static let shared = AppState()

    @Published var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            ConfigStore.save(config)
            applyAll()
        }
    }

    @Published private(set) var devices: [DeviceRef] = []
    /// The last key press, for the Key Monitor. Only one, memory only, and only while that screen is looked at.
    @Published private(set) var lastKey: KeyLogEntry?
    /// Keys held down right now, for the Keyboard screen. Only tracked while it is being looked at.
    @Published private(set) var pressedKeys: Set<UInt64> = []
    @Published private(set) var inputMonitoringGranted = HIDMonitor.hasAccess
    @Published private(set) var accessibilityGranted = ComboEngine.hasAccess
    @Published private(set) var launchAtLogin = LaunchAgent.isEnabled
    @Published private(set) var lastError: String?
    /// Input Monitoring was granted while the app ran, but macOS only applies it to a fresh process.
    @Published private(set) var needsRelaunch = false
    /// The permissions sheet, shown on first launch and from Settings.
    @Published var showsOnboarding = false
    /// Enabled keyboard layouts and the current one, for the Layout Fixer screen.
    @Published private(set) var inputSources: [InputSourceInfo] = []
    @Published private(set) var currentInputSourceID: String?

    /// While set, the next physical key press goes here (the "press a key" buttons in editors).
    @Published var captureHandler: ((HIDKeyEvent) -> Void)?
    /// While set, raw key presses are turned into a shortcut for the shortcut recorder.
    @Published var chordCaptureHandler: ((KeyChord) -> Void)? {
        didSet { chordTracker = ChordTracker() }
    }
    private var chordTracker = ChordTracker()
    /// While set, every raw key press and release (after remaps) goes to the macro recorder.
    var macroCaptureHandler: ((HIDUsage, Bool, Date) -> Void)?
    /// The shortcut recorder also takes a click of an extra mouse button (combo triggers).
    var chordCaptureAcceptsMouse = false

    /// The one recorder listening right now (a Record button, the shortcut or the macro recorder).
    /// Starting another recorder stops this one first.
    @Published private(set) var activeRecorder: UUID?
    /// A text or number field in a macro step is being edited: Return finishes that, it doesn't save the sheet.
    @Published var isEditingMacroField = false
    private var endActiveRecorder: (() -> Void)?
    /// When the last recording ended. The key press that ended it (the recorded key, or Esc) reaches the
    /// window a moment after the raw input, and must not act there (Esc would close the sheet, Return save it).
    private var recordingEndedAt: Date?
    /// When > 0 the app's own window swallows key presses (monitor tab, recorders) so they don't beep or act.
    var swallowLocalKeys = 0

    let hid = HIDMonitor()
    let combos = ComboEngine()
    let layoutFixer = LayoutFixer()

    private var localMonitor: Any?
    /// Keeps App Nap away. A menu bar app with no window open gets napped, and its event taps are then
    /// served late (all at once when the app wakes up), so combos and the layout fixer seem dead.
    private var inputActivity: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var reapplyWork: DispatchWorkItem?
    private let hidutilQueue = DispatchQueue(label: "KeyBindingApp.hidutil")
    /// macOS's Accessibility dialog is triggered at most once per launch, not on every check.
    private var askedForAccessibility = false
    private static let onboardingDoneKey = "onboardingDone"

    /// Which key-showing screens are open, and whether the window is actually in front of the user.
    private var monitorScreenOpen = false
    private var keyboardScreenOpen = false
    private var windowVisible = false

    private override init() {
        config = ConfigStore.load()
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        inputActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Handles keyboard input: remaps, combos and the layout fixer"
        )
        // The key history option is gone; drop its stored setting.
        UserDefaults.standard.removeObject(forKey: "keyMonitorKeepsHistory")
        LaunchAgent.refreshIfNeeded()

        hid.onKey = { [weak self] event in self?.handle(hidEvent: event) }
        hid.isListening = { [weak self] in
            guard let self else { return false }
            return self.isMonitorViewed || self.isKeyboardViewed || self.captureHandler != nil
                || self.chordCaptureHandler != nil || self.macroCaptureHandler != nil
                || (self.layoutFixer.isRunning && self.layoutFixer.trigger == .fn)
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.forgetKeysNoLongerViewed()
                // Leaving the app ends a recording, so macOS's own shortcuts come back.
                if note.name == NSApplication.didResignActiveNotification, let id = self?.activeRecorder {
                    self?.stopRecording(id)
                }
            }
        }
        hid.onDevicesChanged = { [weak self] devices in
            guard let self else { return }
            self.devices = devices
            // A keyboard that was just plugged in has no mapping yet.
            self.scheduleReapply()
        }
        let missing = Permission.allCases.contains { !Permissions.isGranted($0) }
        if (!UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) && missing && !DebugSnapshot.isActive)
            || DebugSnapshot.showsOnboarding {
            // First launch: the welcome sheet explains and asks for both.
            showsOnboarding = true
        } else if !HIDMonitor.hasAccess && !Permissions.wasRequested(.inputMonitoring) && !DebugSnapshot.isActive {
            Permissions.request(.inputMonitoring)
        }
        hid.start()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(localEvent: event)
        }

        // Keys meant for this app (recording a shortcut, the key monitor) must not switch the layout.
        layoutFixer.isPaused = { [weak self] in
            guard let self else { return false }
            return self.combos.isPaused || (NSApp.isActive && self.swallowLocalKeys > 0)
        }
        let center = DistributedNotificationCenter.default()
        let selectedChanged = kTISNotifySelectedKeyboardInputSourceChanged! as String
        let enabledChanged = kTISNotifyEnabledKeyboardInputSourcesChanged! as String
        for name in [selectedChanged, enabledChanged] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                if note.name.rawValue == enabledChanged { self?.layoutFixer.sources.invalidateCache() }
                self?.refreshInputSources()
            }
        }
        refreshInputSources()

        applyAll()
        refreshPermissions()
        // Permissions are granted in System Settings while the app runs; pick them up without a restart.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func refreshPermissions() {
        let input = HIDMonitor.hasAccess
        // A running tap proves the permission even while the check still reports the old state.
        let ax = ComboEngine.hasAccess || combos.isRunning || layoutFixer.isRunning
        if input != inputMonitoringGranted { inputMonitoringGranted = input }
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if input && !hid.isRunning && !hid.start() && !needsRelaunch { needsRelaunch = true }
        updateComboEngine()
        updateLayoutFixer()
        let agent = LaunchAgent.isEnabled
        if agent != launchAtLogin { launchAtLogin = agent }
    }

    // MARK: - Applying

    func applyAll() {
        let config = self.config
        hidutilQueue.async { [weak self] in
            let result = config.enabled
                ? RemapEngine.apply(config.remaps, clearDevices: config.knownDevices)
                : RemapEngine.apply([], clearDevices: config.knownDevices)
            DispatchQueue.main.async {
                self?.lastError = result.ok ? nil : result.messages.joined(separator: "\n")
            }
        }
        updateComboEngine()
        updateLayoutFixer()
    }

    private func scheduleReapply() {
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyAll() }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func updateComboEngine() {
        combos.bindings = config.combos
        let needed = config.enabled && config.combos.contains(where: \.enabled)
        if needed {
            // Try even when the check says no: it can lag behind a fresh grant.
            if !combos.isRunning && !combos.start() { accessibilityMissing() }
        } else if combos.isRunning {
            combos.stop()
        }
    }

    private func updateLayoutFixer() {
        let settings = config.layoutFixer
        if layoutFixer.trigger != settings.trigger { layoutFixer.trigger = settings.trigger }
        if layoutFixer.takesFnFromHID != inputMonitoringGranted {
            layoutFixer.takesFnFromHID = inputMonitoringGranted
            if inputMonitoringGranted {
                os_log("Keyboard reports an fn key: %{public}@", hid.hasKey(page: KeyCatalog.fn.page, usage: KeyCatalog.fn.usage) ? "yes" : "no")
            }
        }
        if settings.enabled {
            if !layoutFixer.isRunning && !layoutFixer.start() { accessibilityMissing() }
        } else if layoutFixer.isRunning {
            layoutFixer.stop()
        }
    }

    /// A feature that needs Accessibility is on but can't start: ask macOS once per launch.
    private func accessibilityMissing() {
        // Not at login: a dialog or System Settings popping up on its own at startup would be a surprise.
        guard !askedForAccessibility, !CommandLine.arguments.contains(LaunchAgent.backgroundArgument),
              !DebugSnapshot.isActive else { return }
        askedForAccessibility = true
        Permissions.request(.accessibility)
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
        showsOnboarding = false
    }

    private func refreshInputSources() {
        let sources = layoutFixer.sources.enabled()
        if sources != inputSources { inputSources = sources }
        currentInputSourceID = layoutFixer.sources.currentID()
    }

    /// The current input language for the menu bar ("EN", "RU").
    var currentLayoutLabel: String? {
        inputSources.first { $0.id == currentInputSourceID }?.shortLabel
    }

    func selectInputSource(_ id: String) {
        layoutFixer.sources.select(id)
    }

    // MARK: - Editing

    func save(_ remap: KeyRemap) {
        var config = self.config
        // One mapping per key and keyboard: replace an older one for the same key.
        config.remaps.removeAll { $0.id != remap.id && $0.from == remap.from && $0.device?.id == remap.device?.id }
        if let index = config.remaps.firstIndex(where: { $0.id == remap.id }) {
            config.remaps[index] = remap
        } else {
            config.remaps.append(remap)
        }
        if let device = remap.device, !config.knownDevices.contains(where: { $0.matches(device) }) {
            config.knownDevices.append(device)
        }
        self.config = config
    }

    func deleteRemaps(_ ids: Set<UUID>) {
        config.remaps.removeAll { ids.contains($0.id) }
    }

    func save(_ combo: ComboBinding) {
        var config = self.config
        config.combos.removeAll { $0.id != combo.id && $0.trigger == combo.trigger }
        if let index = config.combos.firstIndex(where: { $0.id == combo.id }) {
            config.combos[index] = combo
        } else {
            config.combos.append(combo)
        }
        self.config = config
    }

    func deleteCombos(_ ids: Set<UUID>) {
        config.combos.removeAll { ids.contains($0.id) }
    }

    func resetAll() {
        var config = self.config
        config.remaps = []
        config.combos = []
        self.config = config
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try LaunchAgent.enable() } else { try LaunchAgent.disable() }
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = LaunchAgent.isEnabled
    }

    /// What a key from `device` turns into after the active remaps.
    func remapped(_ usage: HIDUsage, from device: DeviceRef) -> HIDUsage {
        guard config.enabled else { return usage }
        let candidates = config.remaps.filter { $0.enabled && $0.from == usage }
        let remap = candidates.first { $0.device?.matches(device) == true } ?? candidates.first { $0.device == nil }
        return remap?.to ?? usage
    }

    /// Keyboards for the pickers: the connected ones, then any a remap still refers to.
    var keyboardChoices: [DeviceRef] {
        var list = devices
        for device in config.remaps.compactMap(\.device) where !list.contains(where: { $0.matches(device) }) {
            list.append(device)
        }
        return list
    }

    func displayName(of device: DeviceRef) -> String {
        devices.contains { $0.matches(device) } ? device.name : device.name + " (not connected)"
    }

    /// The keyboard a new remap or preset is for by default: an external one if connected.
    var defaultKeyboard: DeviceRef? { devices.first { !$0.isBuiltIn && !$0.isMouse } }

    /// Remaps that apply to `device` (nil = show every remap).
    func remaps(for device: DeviceRef?) -> [KeyRemap] {
        guard let device else { return config.remaps }
        return config.remaps.filter { $0.device == nil || $0.device?.matches(device) == true }
    }


    // MARK: - Recording

    /// Starts listening for a recorder. Any other recorder is stopped first. While recording, the app's
    /// window swallows key presses, combos and the layout fixer pause, and macOS's own shortcuts are off.
    /// `onEnd` runs when this recording ends for whatever reason.
    func startRecording(_ id: UUID, onEnd: @escaping () -> Void = {}) {
        if let active = activeRecorder { stopRecording(active) }
        activeRecorder = id
        endActiveRecorder = onEnd
        swallowLocalKeys += 1
        combos.isPaused = true
        if !DebugSnapshot.isSelfTest { SystemShortcuts.disable() }
    }

    func stopRecording(_ id: UUID) {
        guard activeRecorder == id else { return }
        activeRecorder = nil
        captureHandler = nil
        chordCaptureHandler = nil
        macroCaptureHandler = nil
        chordCaptureAcceptsMouse = false
        swallowLocalKeys -= 1
        combos.isPaused = false
        SystemShortcuts.restore()
        recordingEndedAt = Date()
        let end = endActiveRecorder
        endActiveRecorder = nil
        end?()
    }

    // MARK: - Who is looking at key presses

    private var isMonitorViewed: Bool { monitorScreenOpen && windowVisible && NSApp.isActive }
    private var isKeyboardViewed: Bool { keyboardScreenOpen && windowVisible && NSApp.isActive }

    func setMonitorScreenOpen(_ open: Bool) {
        monitorScreenOpen = open
        forgetKeysNoLongerViewed()
    }

    func setKeyboardScreenOpen(_ open: Bool) {
        keyboardScreenOpen = open
        forgetKeysNoLongerViewed()
    }

    /// Called by the window: closed, minimized, hidden behind other windows or on another Space counts as not visible.
    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
        forgetKeysNoLongerViewed()
    }

    /// Drops everything about key presses as soon as nobody can see it.
    private func forgetKeysNoLongerViewed() {
        if !isMonitorViewed && lastKey != nil { lastKey = nil }
        if !isKeyboardViewed && !pressedKeys.isEmpty { pressedKeys.removeAll() }
    }


    // MARK: - Key events

    private func handle(hidEvent: HIDKeyEvent) {
        if hidEvent.usage == KeyCatalog.fn { layoutFixer.handleFnFromHID(isDown: hidEvent.isDown) }
        if let handler = macroCaptureHandler {
            handler(remapped(hidEvent.usage, from: hidEvent.device), hidEvent.isDown, hidEvent.time)
            return
        }
        if let handler = chordCaptureHandler {
            // The raw key is what the keyboard sent; macOS (and the combo engine) sees it after the remaps.
            if let chord = chordTracker.handle(remapped(hidEvent.usage, from: hidEvent.device), isDown: hidEvent.isDown) {
                if chord == KeyChord(keyCode: 0x35, modifiers: []), let id = activeRecorder {
                    stopRecording(id) // Esc alone cancels; Esc can still be picked from the key menu.
                    return
                }
                chordCaptureHandler = nil
                handler(chord)
            }
            return
        }
        let value = hidEvent.usage.hidutilValue
        if isKeyboardViewed {
            if hidEvent.isDown {
                pressedKeys.insert(value)
            } else {
                pressedKeys.remove(value)
            }
        }
        guard hidEvent.isDown else { return }

        // A "press a key" button gets exactly this one press, nothing is kept. Esc cancels it.
        if hidEvent.usage == HIDUsage(page: HIDPage.keyboard, usage: 0x29), captureHandler != nil, let id = activeRecorder {
            stopRecording(id)
            return
        }
        if let handler = captureHandler {
            captureHandler = nil
            handler(hidEvent)
            return
        }
        guard isMonitorViewed else { return }
        lastKey = KeyLogEntry(hid: hidEvent, time: hidEvent.time)
        // Redraw once it is clear whether macOS produced a key event for this press.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.objectWillChange.send() }
    }

    func handle(localEvent event: NSEvent) -> NSEvent? {
        if activeRecorder == nil, event.type == .keyDown, let ended = recordingEndedAt,
           Date().timeIntervalSince(ended) < 0.5 {
            recordingEndedAt = nil
            return nil
        }
        if event.type == .otherMouseDown {
            // A trigger recorder takes the middle, back or forward button (never left or right clicks).
            if activeRecorder != nil, chordCaptureAcceptsMouse, event.buttonNumber >= 2, let handler = chordCaptureHandler {
                chordCaptureHandler = nil
                handler(.mouse(event.buttonNumber, modifiers: ModifierSet(nsFlags: event.modifierFlags).subtracting(.function)))
                return nil
            }
            return event
        }
        if activeRecorder != nil {
            // Without Input Monitoring the shortcut recorder only has the key presses that reach this window.
            if event.type == .keyDown, !inputMonitoringGranted, let handler = chordCaptureHandler {
                chordCaptureHandler = nil
                handler(KeyChord(keyCode: event.keyCode,
                                 modifiers: ModifierSet(nsFlags: event.modifierFlags).subtracting(.function)))
            }
            // Nothing typed while recording reaches the window, not even ⌘ shortcuts.
            return event.type == .keyDown ? nil : event
        }
        if isMonitorViewed { updateLastKey(event) }
        if swallowLocalKeys > 0, event.type == .keyDown, !event.modifierFlags.contains(.command) {
            return nil
        }
        return event
    }

    /// Adds what macOS made of a key press to the monitor's entry for it.
    private func updateLastKey(_ event: NSEvent) {
        let isModifier = event.type == .flagsChanged
        let modifiers = ModifierSet(nsFlags: event.modifierFlags)
        // Attach what macOS produced to the raw press that just happened, if there is one.
        if var entry = lastKey, entry.macKeyCode == nil, Date().timeIntervalSince(entry.time) < 0.4 {
            entry.macKeyCode = event.keyCode
            entry.characters = isModifier ? nil : event.characters
            entry.macModifiers = modifiers
            lastKey = entry
        } else if !inputMonitoringGranted {
            // Without Input Monitoring this is the only source of information.
            lastKey = KeyLogEntry(hid: nil, macKeyCode: event.keyCode, characters: isModifier ? nil : event.characters,
                                  macModifiers: modifiers, time: Date())
        }
    }
}
