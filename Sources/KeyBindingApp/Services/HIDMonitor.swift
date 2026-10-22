import Foundation
import IOKit
import IOKit.hid

/// A raw key press as the keyboard reported it, before macOS translated it.
struct HIDKeyEvent: Identifiable, Equatable {
    let id = UUID()
    let usage: HIDUsage
    let isDown: Bool
    let device: DeviceRef
    let time: Date
}

/// Reads every keyboard through IOHIDManager. This sees keys that macOS itself ignores,
/// and tells which keyboard a press came from. Needs the Input Monitoring permission.
final class HIDMonitor {
    var onKey: ((HIDKeyEvent) -> Void)?
    /// Key presses are dropped right away unless something on screen needs them.
    var isListening: () -> Bool = { false }
    /// Called when a keyboard is connected or disconnected.
    var onDevicesChanged: (([DeviceRef]) -> Void)?

    private(set) var devices: [DeviceRef] = []
    private var keyStates = KeyStateFilter()
    private var manager: IOHIDManager?

    var isRunning: Bool { manager != nil }

    @discardableResult
    func start() -> Bool {
        guard manager == nil else { return true }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().handle(value: value)
        }, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().refreshDevices()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().refreshDevices()
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("KeyBindingApp: IOHIDManagerOpen failed: \(result)")
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return false
        }
        self.manager = manager
        refreshDevices()
        return true
    }

    /// Whether a connected keyboard has this key (e.g. fn on the Apple vendor page).
    func hasKey(page: UInt32, usage: UInt32) -> Bool {
        guard let manager, let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        let matching = [kIOHIDElementUsagePageKey: page, kIOHIDElementUsageKey: usage] as CFDictionary
        return set.contains { device in
            ((IOHIDDeviceCopyMatchingElements(device, matching, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []).isEmpty == false
        }
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func refreshDevices() {
        guard let manager, let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            devices = []
            onDevicesChanged?(devices)
            return
        }
        devices = Self.keyboards(in: set)
        onDevicesChanged?(devices)
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        switch page {
        case HIDPage.keyboard:
            // 0x00...0x03 are error/rollover codes; above 0xE7 is reserved.
            guard usage >= 0x04, usage <= 0xE7 else { return }
        case HIDPage.consumer, HIDPage.appleVendorTopCase:
            guard usage > 0 else { return }
        default:
            return
        }
        // Keys report 1 on press and 0 on release; anything else is not a key state.
        let raw = IOHIDValueGetIntegerValue(value)
        guard raw == 0 || raw == 1 else { return }
        let pressed = raw == 1
        let device = Self.deviceRef(IOHIDElementGetDevice(element))
        // Up/down state is kept even when nobody listens (only which keys are down right now, no history):
        // otherwise a key released while not listening would still count as down, and its next press be lost.
        guard keyStates.accept("\(device.id)/\(page)/\(usage)", pressed: pressed) else { return }
        guard isListening() else { return }
        onKey?(HIDKeyEvent(usage: HIDUsage(page: page, usage: usage), isDown: pressed, device: device, time: Date()))
    }

    /// Devices that send key presses: keyboards, and mice whose extra buttons send keys.
    /// The headphone jack's media buttons also match the manager but are not listed (see isKeyboard).
    /// One entry per device, the built-in keyboard first.
    static func keyboards(in set: Set<IOHIDDevice>) -> [DeviceRef] {
        var seen = Set<String>()
        return set.filter(isKeyboard).map(deviceRef)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.sortGroup, $0.name) < ($1.sortGroup, $1.name) }
    }

    private static func deviceRef(_ device: IOHIDDevice) -> DeviceRef {
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        if isBuiltInKeyboard(device) {
            return DeviceRef(vendorID: vendor, productID: product, name: "MacBook keyboard (built-in)", isBuiltIn: true)
        }
        var name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        if name.isEmpty { name = String(format: "Keyboard %04X:%04X", vendor, product) }
        let isMouse = usagePairs(device).contains([kHIDPage_GenericDesktop, kHIDUsage_GD_Mouse])
        return DeviceRef(vendorID: vendor, productID: product, name: name, isMouse: isMouse)
    }

    /// The (page, usage) pairs a device declares, e.g. 1/6 keyboard, 1/2 mouse, 12/1 media buttons.
    private static func usagePairs(_ device: IOHIDDevice) -> Set<[Int]> {
        let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        return Set(pairs.map { [$0[kIOHIDDeviceUsagePageKey] ?? 0, $0[kIOHIDDeviceUsageKey] ?? 0] })
    }

    private static func isBuiltInKeyboard(_ device: IOHIDDevice) -> Bool {
        let builtIn = (IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? Bool) ?? false
        return builtIn && usagePairs(device).contains([kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard])
    }

    /// Declares a keyboard interface (1/6), so hidutil can remap its keys. Mice with programmable
    /// buttons do; the headphone jack's media buttons (12/1 only) don't.
    private static func isKeyboard(_ device: IOHIDDevice) -> Bool {
        usagePairs(device).contains([kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard])
    }

    // MARK: - Permission

    static var hasAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt the first time; afterwards the user must enable it in System Settings.
    @discardableResult
    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}

/// Drops repeated reports of the same key state. Some keyboards (the MacBook's own) show up as two HID
/// devices and report every press twice; a "down" for a key that is already down is not a new press.
/// It must see every event, listened to or not, or a missed release would swallow the next press.
struct KeyStateFilter {
    private var down: Set<String> = []

    mutating func accept(_ key: String, pressed: Bool) -> Bool {
        pressed ? down.insert(key).inserted : down.remove(key) != nil
    }
}
