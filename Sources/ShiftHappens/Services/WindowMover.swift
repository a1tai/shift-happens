import AppKit
import ApplicationServices

/// Where a window goes. All frames are in Accessibility coordinates: origin at the top left of the main
/// screen, y growing down, the way AXPosition reports windows on every screen.
enum WindowLayout {
    /// A screen's visible area (without menu bar and Dock) in Accessibility coordinates. `mainHeight` is the
    /// height of the main screen, whose bottom-left corner is the origin of AppKit's coordinates.
    static func axFrame(ofAppKit frame: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The screen the window is on: the one holding the window's center, else the one it overlaps most.
    static func screen(for window: CGRect, among screens: [CGRect]) -> CGRect? {
        let center = CGPoint(x: window.midX, y: window.midY)
        if let holding = screens.first(where: { $0.contains(center) }) { return holding }
        return screens.max { overlap($0, window) < overlap($1, window) }
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// The frame for Maximize, Left Half or Right Half within a screen's visible area (whole points).
    static func target(_ action: WindowAction, in visible: CGRect) -> CGRect? {
        let half = (visible.width / 2).rounded(.down)
        switch action {
        case .maximize: return visible
        case .leftHalf: return CGRect(x: visible.minX, y: visible.minY, width: half, height: visible.height)
        case .rightHalf: return CGRect(x: visible.minX + half, y: visible.minY, width: visible.width - half, height: visible.height)
        case .restore: return nil
        }
    }

    static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// Remembers, per window, the frame it had before the app first moved it, so Restore can put it back.
/// Several moves in a row (Left Half, then Maximize) keep the frame from before the first one.
/// In memory only, for the last few windows.
struct WindowMemory<Key> {
    private var entries: [(key: Key, original: CGRect, placed: CGRect)] = []
    private let same: (Key, Key) -> Bool
    static var limit: Int { 20 }

    init(same: @escaping (Key, Key) -> Bool) { self.same = same }

    /// Notes that the app moves `key` from `current` to `placed`.
    mutating func willMove(_ key: Key, from current: CGRect, to placed: CGRect) {
        let index = entries.firstIndex { same($0.key, key) }
        // Still where the app put it last time: keep the frame from before that move.
        let original = index.flatMap { WindowLayout.isClose(entries[$0].placed, current) ? entries[$0].original : nil } ?? current
        if let index { entries.remove(at: index) }
        entries.append((key, original, placed))
        if entries.count > Self.limit { entries.removeFirst() }
    }

    /// The frame to restore, forgotten once taken.
    mutating func takeOriginal(of key: Key) -> CGRect? {
        guard let index = entries.firstIndex(where: { same($0.key, key) }) else { return nil }
        return entries.remove(at: index).original
    }
}

/// Moves the front window with the Accessibility API (the permission combos already need).
final class WindowMover {
    private var memory = WindowMemory<AXUIElement>(same: { CFEqual($0, $1) })

    /// Returns false when there is no window to move or it can't be moved or resized (then nothing changes).
    func perform(_ action: WindowAction) -> Bool {
        guard let window = Self.frontWindow(), let current = Self.frame(of: window) else { return false }
        if action == .restore {
            guard let original = memory.takeOriginal(of: window) else { return false }
            return Self.setFrame(original, of: window)
        }
        if (Self.attribute(window, "AXFullScreen") as? Bool) == true { return false }
        guard Self.isSettable(window, kAXSizeAttribute), Self.isSettable(window, kAXPositionAttribute),
              let main = NSScreen.screens.first else { return false }
        let screens = NSScreen.screens.map { WindowLayout.axFrame(ofAppKit: $0.visibleFrame, mainHeight: main.frame.height) }
        guard let visible = WindowLayout.screen(for: current, among: screens),
              let target = WindowLayout.target(action, in: visible) else { return false }
        memory.willMove(window, from: current, to: target)
        return Self.setFrame(target, of: window)
    }

    private static func frontWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window = attribute(app, kAXFocusedWindowAttribute) else { return nil }
        return (window as! AXUIElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// Size, then position, then size again: apps limit a window's size to the screen it is on at that moment,
    /// so a window moving to a larger screen needs the second size.
    private static func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        var origin = frame.origin, size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return false }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent) == .success
        return moved && sized
    }
}
