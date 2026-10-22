import Foundation

/// Applies key-to-key remaps with the system tool `hidutil` (UserKeyMapping).
/// The mapping lives in the HID driver, so it works in every app and needs no extra permission,
/// but it is reset on reboot and on reconnect; the app reapplies it in both cases.
enum RemapEngine {
    private static let hidutil = "/usr/bin/hidutil"

    struct Result {
        var ok = true
        var messages: [String] = []
    }

    /// Applies `remaps` (only the enabled ones) and clears mappings on devices in `clearDevices`
    /// that no longer have any. Global remaps go to every keyboard; per-device ones are merged on top.
    @discardableResult
    static func apply(_ remaps: [KeyRemap], clearDevices: [DeviceRef]) -> Result {
        let active = remaps.filter(\.enabled)
        let global = active.filter { $0.device == nil }
        var result = Result()

        // Global first: `--set` without `--matching` overwrites every keyboard's mapping.
        run(arguments: ["property", "--set", mappingJSON(global)], into: &result)

        var devices: [DeviceRef] = []
        for remap in active {
            if let device = remap.device, !devices.contains(where: { $0.matches(device) }) {
                devices.append(device)
            }
        }
        for device in devices {
            // A device-specific remap wins over a global remap of the same key.
            let own = active.filter { $0.device?.matches(device) == true }
            let ownSources = Set(own.map(\.from))
            let merged = global.filter { !ownSources.contains($0.from) } + own
            run(arguments: ["property", "--matching", matchingJSON(device), "--set", mappingJSON(merged)], into: &result)
        }
        for device in clearDevices where !devices.contains(where: { $0.matches(device) }) {
            run(arguments: ["property", "--matching", matchingJSON(device), "--set", mappingJSON(global)], into: &result)
        }
        return result
    }

    static func clearAll(devices: [DeviceRef]) {
        apply([], clearDevices: devices)
    }

    static func mappingJSON(_ remaps: [KeyRemap]) -> String {
        let items = remaps.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.from.hidutilValue),\"HIDKeyboardModifierMappingDst\":\($0.to.hidutilValue)}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    static func matchingJSON(_ device: DeviceRef) -> String {
        "{\"VendorID\":\(device.vendorID),\"ProductID\":\(device.productID)}"
    }

    /// The equivalent Terminal command, shown in the UI for transparency.
    static func shellCommand(for remaps: [KeyRemap]) -> String {
        let active = remaps.filter(\.enabled)
        let global = active.filter { $0.device == nil }
        var lines = ["hidutil property --set '\(mappingJSON(global))'"]
        let devices = Dictionary(grouping: active.compactMap(\.device), by: \.id).values.compactMap(\.first)
        for device in devices {
            let own = active.filter { $0.device?.matches(device) == true }
            let ownSources = Set(own.map(\.from))
            let merged = global.filter { !ownSources.contains($0.from) } + own
            lines.append("hidutil property --matching '\(matchingJSON(device))' --set '\(mappingJSON(merged))'")
        }
        return lines.joined(separator: "\n")
    }

    private static func run(arguments: [String], into result: inout Result) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hidutil)
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                result.ok = false
                result.messages.append("hidutil \(arguments.joined(separator: " ")): \(err)")
            }
        } catch {
            result.ok = false
            result.messages.append("Couldn't run hidutil: \(error.localizedDescription)")
        }
    }
}
