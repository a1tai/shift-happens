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
        var seen = Set<String>()
        devices = set.map(Self.deviceRef).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
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
        onKey?(HIDKeyEvent(usage: HIDUsage(page: page, usage: usage), isDown: pressed, device: device, time: Date()))
    }

    private static func deviceRef(_ device: IOHIDDevice) -> DeviceRef {
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        var name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        if name.isEmpty { name = String(format: "Клавиатура %04X:%04X", vendor, product) }
        return DeviceRef(vendorID: vendor, productID: product, name: name)
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
