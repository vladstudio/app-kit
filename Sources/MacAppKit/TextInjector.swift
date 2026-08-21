// Text injection into the frontmost app: keycode-first (Screen Sharing-safe),
// with clipboard-paste fallback for chars unresolvable in the current layout.
import AppKit
import Carbon

/// Inject text into the active app.
///
/// Strategy: resolve each character to a real keycode in the current keyboard
/// layout and emit per-character key events. Receivers like Screen Sharing
/// forward keycodes (not the unicode string payload), so this is the reliable
/// path locally and remotely. If ANY character can't be resolved — emoji, CJK,
/// accents not on the active layout — fall back to a single layout-agnostic
/// clipboard paste (Cmd+V) for the whole text.
///
/// We intentionally do NOT switch to Cmd+V for long text. Paste over Screen
/// Sharing fails: the local pasteboard isn't the remote's, and the synthetic
/// Cmd+V often arrives as a bare `v` with the modifier stripped in transit.
/// Per-char keycodes are slower for long text but reliable.
///
/// - Important: Must be called on the main thread (touches `NSPasteboard`).
@MainActor
public enum TextInjector {
    /// Inject `text`.
    ///
    /// - Parameter marker: Value written to each emitted event's
    ///   `eventSourceUserData` field, so callers running a `CGEventTap`
    ///   (e.g. key remappers) can skip their own synthetic events. Pass nil
    ///   to emit untagged events.
    /// - Returns: `false` if the event source could not be created and nothing
    ///   was posted; `true` otherwise (including for empty input).
    @discardableResult
    public static func inject(_ text: String, marker: Int64? = nil) -> Bool {
        guard !text.isEmpty else { return true }
        let map = charCodeMap()
        if text.allSatisfy({ map[$0] != nil }) {
            return injectKeys(text, map: map, marker: marker)
        }
        // Any unresolvable char (emoji, CJK, accents not on the layout) forces a
        // single paste for the whole text. Per-char pastes would race the
        // async clipboard restore and corrupt the user's original pasteboard.
        return injectViaPaste(text, marker: marker)
    }

    // MARK: - Keycode injection

    /// char -> (keycode, needsShift) for the current keyboard layout, built per call.
    private static func charCodeMap() -> [Character: (code: UInt16, shift: Bool)] {
        var m: [Character: (UInt16, Bool)] = [:]
        for code in UInt16(0)...127 {
            if let s = translateKeyCode(code), let c = s.first { m[c] = (code, false) }
            if let s = translateKeyCode(code, modifiers: 1 << 1), let c = s.first, m[c] == nil {
                m[c] = (code, true)
            }
        }
        return m
    }

    private static func injectKeys(_ text: String,
                                   map: [Character: (code: UInt16, shift: Bool)],
                                   marker: Int64?) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for ch in text {
            guard let (code, shift) = map[ch] else { return false }
            var utf16 = [UniChar](String(ch).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            if shift {
                down.flags.insert(.maskShift); up.flags.insert(.maskShift)
            } else {
                down.flags.subtract(.maskShift); up.flags.subtract(.maskShift)
            }
            tag(down, marker: marker); tag(up, marker: marker)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
        return true
    }

    // MARK: - Clipboard paste fallback

    @discardableResult
    private static func injectViaPaste(_ text: String, marker: Int64?) -> Bool {
        let snapshot = ClipboardSnapshot.save()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        tag(down, marker: marker); tag(up, marker: marker)
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        // Restore after the paste has been consumed. Retry briefly if the paste
        // hasn't yet bumped the changeCount (slow receivers).
        let changeCount = pb.changeCount
        func tryRestore(_ attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if NSPasteboard.general.changeCount == changeCount || attempt >= 3 {
                    snapshot.restore()
                } else {
                    tryRestore(attempt + 1)
                }
            }
        }
        tryRestore()
        return true
    }

    // MARK: - Helpers

    private static func tag(_ event: CGEvent, marker: Int64?) {
        if let marker { event.setIntegerValueField(.eventSourceUserData, value: marker) }
    }

    /// Convert a hardware keycode to its character using the current keyboard layout.
    private static func translateKeyCode(_ code: UInt16, modifiers: UInt32 = 0) -> String? {
        guard let sourceRef = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(sourceRef, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        _ = layout.withUnsafeBytes {
            UCKeyTranslate($0.bindMemory(to: UCKeyboardLayout.self).baseAddress!,
                           code, UInt16(kUCKeyActionDown), modifiers,
                           UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                           &deadKeyState, 4, &len, &chars)
        }
        return len > 0 ? String(utf16CodeUnits: chars, count: len) : nil
    }
}