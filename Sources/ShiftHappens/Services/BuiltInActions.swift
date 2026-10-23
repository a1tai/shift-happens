import AppKit

/// What a combo can do besides sending keys or opening an app.
enum BuiltInAction: Codable, Hashable {
    /// Pastes the clipboard's text without its formatting, in any app. The clipboard is put back afterwards.
    case pastePlainText
    /// Changes the case of the selected text. The clipboard is put back afterwards.
    case changeCase(TextCase)
    /// Moves and resizes the front window.
    case window(WindowAction)
    /// Runs one of the user's shortcuts from the Shortcuts app, by name.
    case runShortcut(String)

    static let maxShortcutName = 255

    var display: String {
        switch self {
        case .pastePlainText: return "Paste as Plain Text"
        case .changeCase(let textCase): return "Change Case: " + textCase.title
        case .window(let action): return action.title
        case .runShortcut(let name): return "Run “\(name)”"
        }
    }

    /// The name in the action menu, where the group heading (Text, Window) already says the rest.
    var menuTitle: String {
        switch self {
        case .changeCase(let textCase): return textCase.title
        default: return display
        }
    }

    var systemImage: String {
        switch self {
        case .pastePlainText: return "doc.plaintext"
        case .changeCase: return "textformat"
        case .window(let action): return action.systemImage
        case .runShortcut: return "square.stack.3d.up"
        }
    }

    /// A shortcut name of reasonable length, on one line. Anything else read from a file is dropped.
    func sanitized() -> BuiltInAction? {
        switch self {
        case .pastePlainText, .changeCase, .window:
            return self
        case .runShortcut(let name):
            let valid = !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= Self.maxShortcutName
                && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            return valid ? self : nil
        }
    }
}

enum TextCase: String, Codable, CaseIterable {
    case upper, lower, title

    var title: String {
        switch self {
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .title: return "Title Case"
        }
    }
}

enum WindowAction: String, Codable, CaseIterable {
    case maximize, leftHalf, rightHalf, restore

    var title: String {
        switch self {
        case .maximize: return "Maximize Window"
        case .leftHalf: return "Window to Left Half"
        case .rightHalf: return "Window to Right Half"
        case .restore: return "Restore Window"
        }
    }

    var systemImage: String {
        switch self {
        case .maximize: return "macwindow"
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .restore: return "arrow.uturn.backward"
        }
    }
}

/// Everything on a pasteboard, every item with every type, so it can be put back exactly.
struct PasteboardSnapshot {
    let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    var isEmpty: Bool { items.isEmpty }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData { item.setData(data, forType: type) }
            return item
        })
    }
}

/// Paste as Plain Text: the clipboard's text goes in without fonts, colors or links.
enum PlainTextPaste {
    /// The clipboard's text without formatting: its plain text if there is some, else the text of its RTF or HTML.
    static func plainText(in pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string), !string.isEmpty { return string }
        let documents: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] =
            [(.rtf, .rtf), (.rtfd, .rtfd), (.html, .html)]
        for (type, documentType) in documents {
            guard let data = pasteboard.data(forType: type),
                  let text = try? NSAttributedString(data: data, options: [.documentType: documentType],
                                                     documentAttributes: nil).string,
                  !text.isEmpty else { continue }
            return text
        }
        return nil
    }

    /// Long texts take some apps a moment to paste; the clipboard must not change back before that.
    static func restoreDelay(charCount: Int) -> TimeInterval {
        min(3, 0.5 + 0.0005 * TimeInterval(charCount))
    }

    /// Puts only the plain text on the clipboard, pastes it, and later puts the old clipboard back, unless
    /// something else changed the clipboard in the meantime. Without text on the clipboard it does nothing
    /// and returns false. Main thread only.
    @discardableResult
    static func run(on pasteboard: NSPasteboard = .general, paste: () -> Void,
                    after: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                    }) -> Bool {
        guard let text = plainText(in: pasteboard) else { return false }
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount
        paste()
        after(restoreDelay(charCount: text.count)) {
            guard pasteboard.changeCount == ours else { return }
            snapshot.restore(to: pasteboard)
        }
        return true
    }
}

/// The Shortcuts app's command line tool. Run with an argument list, never through a shell.
enum ShortcutsRunner {
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// The user's shortcuts, by name. Blocks for up to a few seconds: call it off the main thread.
    static func list() -> [String] {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["list"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map(String.init)
            .filter { BuiltInAction.runShortcut($0).sanitized() != nil }
    }

    /// Runs a shortcut without waiting for it. `completion` gets an error message, or nil when it worked,
    /// on the main thread. A shortcut still running after `timeout` seconds is stopped.
    static func run(_ name: String, timeout: TimeInterval = 120, completion: @escaping (String?) -> Void) {
        let process = Process()
        process.executableURL = tool
        // "--" so a name that starts with a dash is never read as an option.
        process.arguments = ["run", "--", name]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        var timedOut = false
        let stop = DispatchWorkItem {
            if process.isRunning { timedOut = true; process.terminate() }
        }
        process.terminationHandler = { process in
            stop.cancel()
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let failure: String? = timedOut ? "Shortcut “\(name)” took longer than \(Int(timeout)) s and was stopped."
                : process.terminationStatus == 0 ? nil
                : "Shortcut “\(name)” failed" + (message.isEmpty ? "." : ": \(message.prefix(200))")
            DispatchQueue.main.async { completion(failure) }
        }
        do {
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        } catch {
            DispatchQueue.main.async { completion("Can't run Shortcuts: \(error.localizedDescription)") }
        }
    }
}
