import AppKit
import Combine
import Foundation

/// One line of the key monitor: what the keyboard sent and what macOS made of it.
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

/// The app's single source of truth: saved config, live keyboard state and the two engines.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            ConfigStore.save(config)
            applyAll()
        }
    }

    @Published private(set) var devices: [DeviceRef] = []
    @Published private(set) var log: [KeyLogEntry] = []
    @Published private(set) var pressedKeys: Set<UInt64> = []
    @Published private(set) var inputMonitoringGranted = HIDMonitor.hasAccess
    @Published private(set) var accessibilityGranted = ComboEngine.hasAccess
    @Published private(set) var launchAtLogin = LaunchAgent.isEnabled
    @Published private(set) var lastError: String?

    /// While set, the next physical key press goes here (the "press a key" buttons in editors).
    @Published var captureHandler: ((HIDKeyEvent) -> Void)?
    /// When > 0 the app's own window swallows key presses (monitor tab, recorders) so they don't beep or act.
    var swallowLocalKeys = 0

    let hid = HIDMonitor()
    let combos = ComboEngine()

    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var reapplyWork: DispatchWorkItem?
    private let hidutilQueue = DispatchQueue(label: "KeyBindingApp.hidutil")

    private init() {
        config = ConfigStore.load()
    }

    // MARK: - Lifecycle

    func start() {
        LaunchAgent.refreshIfNeeded()

        hid.onKey = { [weak self] event in self?.handle(hidEvent: event) }
        hid.onDevicesChanged = { [weak self] devices in
            guard let self else { return }
            self.devices = devices
            // A keyboard that was just plugged in has no mapping yet.
            self.scheduleReapply()
        }
        if !HIDMonitor.hasAccess { HIDMonitor.requestAccess() }
        hid.start()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(localEvent: event)
        }

        applyAll()
        refreshPermissions()
        // Permissions are granted in System Settings while the app runs; pick them up without a restart.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func refreshPermissions() {
        let input = HIDMonitor.hasAccess
        let ax = ComboEngine.hasAccess
        if input != inputMonitoringGranted { inputMonitoringGranted = input }
        if ax != accessibilityGranted { accessibilityGranted = ax }
        if input && !hid.isRunning { hid.start() }
        updateComboEngine()
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
        if needed && accessibilityGranted {
            if !combos.isRunning && !combos.start() {
                lastError = "Couldn't intercept keys. Check the Accessibility permission."
            }
        } else if combos.isRunning {
            combos.stop()
        }
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

    /// Remaps that apply to `device` (nil = show every remap).
    func remaps(for device: DeviceRef?) -> [KeyRemap] {
        guard let device else { return config.remaps }
        return config.remaps.filter { $0.device == nil || $0.device?.matches(device) == true }
    }

    func clearLog() { log.removeAll() }

    // MARK: - Key events

    private func handle(hidEvent: HIDKeyEvent) {
        let value = hidEvent.usage.hidutilValue
        if hidEvent.isDown {
            pressedKeys.insert(value)
        } else {
            pressedKeys.remove(value)
        }
        guard hidEvent.isDown else { return }

        if let handler = captureHandler {
            captureHandler = nil
            handler(hidEvent)
        }
        log.insert(KeyLogEntry(hid: hidEvent, time: hidEvent.time), at: 0)
        if log.count > 100 { log.removeLast(log.count - 100) }
        // Redraw once it is clear whether macOS produced a key event for this press.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.objectWillChange.send() }
    }

    private func handle(localEvent event: NSEvent) -> NSEvent? {
        let isModifier = event.type == .flagsChanged
        let modifiers = ModifierSet(nsFlags: event.modifierFlags)
        // Attach what macOS produced to the raw press that just happened, if there is one.
        if let index = log.firstIndex(where: { $0.macKeyCode == nil }),
           index == 0, Date().timeIntervalSince(log[index].time) < 0.4 {
            log[index].macKeyCode = event.keyCode
            log[index].characters = isModifier ? nil : event.characters
            log[index].macModifiers = modifiers
        } else if !inputMonitoringGranted {
            // Without Input Monitoring this is the only source of information.
            log.insert(KeyLogEntry(hid: nil, macKeyCode: event.keyCode,
                                   characters: isModifier ? nil : event.characters,
                                   macModifiers: modifiers, time: Date()), at: 0)
        }
        if swallowLocalKeys > 0, event.type == .keyDown, !event.modifierFlags.contains(.command) {
            return nil
        }
        return event
    }
}
