import AppKit

/// Change Case: copies the selection, changes its case and pastes it back over the selection.
/// The clipboard is put back afterwards, as with Paste as Plain Text.
enum CaseChange {
    /// The text in another case. Title Case capitalizes the first letter of every word and lowercases the rest.
    static func transform(_ text: String, to textCase: TextCase, locale: Locale = .current) -> String {
        switch textCase {
        case .upper: return text.uppercased(with: locale)
        case .lower: return text.lowercased(with: locale)
        case .title:
            var result = ""
            var startsWord = true
            for character in text {
                if character.isLetter || character.isNumber {
                    result += startsWord ? String(character).uppercased(with: locale) : String(character).lowercased(with: locale)
                    startsWord = false
                } else {
                    result.append(character)
                    // An apostrophe inside a word (don't, l'eau) keeps the word going; anything else ends it.
                    startsWord = !(character == "'" || character == "’")
                }
            }
            return result
        }
    }

    /// Waits for the copy to land on the clipboard: checks `isDone` every 50 ms, at most 10 times.
    static func poll(_ isDone: @escaping () -> Bool, then: @escaping (Bool) -> Void) {
        func check(_ attempt: Int) {
            if isDone() { return then(true) }
            guard attempt < 10 else { return then(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { check(attempt + 1) }
        }
        check(0)
    }

    /// Copies the selection with `copy`, then pastes it in `textCase` with `paste`. Calls `failed` (and leaves
    /// the clipboard as it was) when nothing was copied, i.e. nothing was selected. Main thread only.
    static func run(_ textCase: TextCase, on pasteboard: NSPasteboard = .general,
                    copy: () -> Void, paste: @escaping () -> Void, failed: @escaping () -> Void,
                    wait: (@escaping () -> Bool, @escaping (Bool) -> Void) -> Void = poll,
                    after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                    }) {
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        copy()
        wait({ pasteboard.changeCount != before }) { copied in
            guard copied else { return failed() }
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
                snapshot.restore(to: pasteboard)
                return failed()
            }
            let changed = transform(text, to: textCase)
            guard changed != text else {
                // Already in that case: leave the selection alone, just give the clipboard back.
                snapshot.restore(to: pasteboard)
                return
            }
            pasteboard.clearContents()
            pasteboard.setString(changed, forType: .string)
            let ours = pasteboard.changeCount
            paste()
            after(PlainTextPaste.restoreDelay(charCount: changed.count)) {
                guard pasteboard.changeCount == ours else { return }
                snapshot.restore(to: pasteboard)
            }
        }
    }
}
