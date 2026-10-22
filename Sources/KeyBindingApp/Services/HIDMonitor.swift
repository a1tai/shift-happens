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
        guard isListening() else { return }
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
        onKey?(HIDKeyEvent(usage: HIDUsage(page: page, usage: usage), isDown: pressed, device: device, time: Date()))
    }

    /// Media buttons (headsets) and mice with programmable buttons also match the manager;
    /// only real keyboards are listed, one entry per keyboard, the built-in one first.
    static func keyboards(in set: Set<IOHIDDevice>) -> [DeviceRef] {
        var seen = Set<String>()
        return set.filter(isKeyboard).map(deviceRef)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.isBuiltIn ? 0 : 1, $0.name) < ($1.isBuiltIn ? 0 : 1, $1.name) }
    }

    private static func deviceRef(_ device: IOHIDDevice) -> DeviceRef {
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        if isBuiltInKeyboard(device) {
            return DeviceRef(vendorID: vendor, productID: product, name: "MacBook keyboard (built-in)", isBuiltIn: true)
        }
        var name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        if name.isEmpty { name = String(format: "Keyboard %04X:%04X", vendor, product) }
        return DeviceRef(vendorID: vendor, productID: product, name: name)
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

    /// A keyboard, not a headset with volume buttons or a mouse that can also send keys.
    private static func isKeyboard(_ device: IOHIDDevice) -> Bool {
        let pairs = usagePairs(device)
        guard pairs.contains([kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard]) else { return false }
        return isBuiltInKeyboard(device) || !pairs.contains([kHIDPage_GenericDesktop, kHIDUsage_GD_Mouse])
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
