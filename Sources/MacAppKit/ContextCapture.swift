import AppKit

/// Captures text from the active app via Accessibility API with clipboard fallback.
@MainActor
public enum ContextCapture {
    /// Capture selected text only (for text transformation workflows).
    public static func captureSelected() async -> String? {
        if let text = selectedViaAX() { return text }
        return await probeSelection()
    }

    /// Capture all text context: selected text first, then full field value.
    public static func captureContext() async -> String? {
        if let text = contextViaAX() { return text }
        return await probeSelection().map { String($0.suffix(1000)) }
    }

    // MARK: - AX: selected text only

    private static func selectedViaAX() -> String? {
        guard let el = focusedElement() else { return nil }
        let text: String? = axAttr(el, kAXSelectedTextAttribute)
        // A whitespace-only "selection" (some apps report one at the caret)
        // is not a selection — let the probe/clipboard paths take over.
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    // MARK: - AX: full context (value + selected)

    private static func contextViaAX() -> String? {
        guard let el = focusedElement() else { return nil }
        let text: String? = axAttr(el, kAXValueAttribute) ?? axAttr(el, kAXSelectedTextAttribute)
        guard let text, !text.isEmpty else { return nil }
        return String(text.suffix(1000))
    }

    // MARK: - Clipboard probe (Electron/web apps)

    /// Posts a synthetic Cmd+C and returns whatever the app copied, with the
    /// clipboard snapshot-protected (any write is rolled back). Targets `app`
    /// directly if given — works for background apps, no focus change —
    /// otherwise the frontmost app. nil if nothing (usable) was copied.
    public static func probeSelection(in app: NSRunningApplication? = nil) async -> String? {
        let pb = NSPasteboard.general
        let savedCount = pb.changeCount
        let snapshot = ClipboardSnapshot.save()

        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if let app {
            down.postToPid(app.processIdentifier)
            up.postToPid(app.processIdentifier)
        } else {
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }

        // Poll for the copy: apps respond at different speeds, and a late
        // write must not be mistaken for "nothing copied". Any change means
        // the app may have clobbered the user's clipboard (e.g. VS Code
        // writing an empty line copy) — roll the snapshot back either way.
        var text: String?
        var changed = false
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pb.changeCount != savedCount {
                changed = true
                if let s = pb.string(forType: .string),
                   !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = s
                }
                break
            }
        }
        if changed { snapshot.restore() }
        return text
    }

    // MARK: - Helpers

    private static func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return axAttr(axApp, kAXFocusedUIElementAttribute)
    }

    private static func axAttr<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? T
    }
}
