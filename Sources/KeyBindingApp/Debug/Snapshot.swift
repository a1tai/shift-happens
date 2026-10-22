import AppKit

/// Debug builds only: renders the app's windows to PNG files so the layout can be checked
/// without Screen Recording access. Driven by environment variables:
/// KB_SNAPSHOT=<file.png>, KB_SCREEN=<keyboard|monitor|remaps|combos|settings>,
/// KB_SIZE=<width>x<height>, KB_EDIT=1 (opens the remap editor for Esc on the Keyboard screen).
enum DebugSnapshot {
    #if DEBUG
    private static let env = ProcessInfo.processInfo.environment
    static var initialScreen: SidebarItem? { env["KB_SCREEN"].flatMap(SidebarItem.init(rawValue:)) }
    static var opensEditor: Bool { env["KB_EDIT"] == "1" }

    static func runIfRequested(window: NSWindow) {
        guard let path = env["KB_SNAPSHOT"] else { return }
        if let size = env["KB_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            window.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let target = window.attachedSheet ?? window
            guard let view = target.contentView?.superview ?? target.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
    #else
    static var initialScreen: SidebarItem? { nil }
    static var opensEditor: Bool { false }
    static func runIfRequested(window: NSWindow) {}
    #endif
}
