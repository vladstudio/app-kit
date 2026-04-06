import AppKit

/// Captures text from the active app via Accessibility API with clipboard fallback.
@MainActor
public enum ContextCapture {
    /// Capture selected text only (for text transformation workflows).
    public static func captureSelected() async -> String? {
        if let text = selectedViaAX() { return text }
        return await selectedViaClipboard()
    }

    /// Capture all text context: selected text first, then full field value.
    public static func captureContext() async -> String? {
        if let text = contextViaAX() { return text }
        return await selectedViaClipboard()
    }

    // MARK: - AX: selected text only

    private static func selectedViaAX() -> String? {
        guard let el = focusedElement() else { return nil }
        let text: String? = axAttr(el, kAXSelectedTextAttribute)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - AX: full context (value + selected)

    private static func contextViaAX() -> String? {
        guard let el = focusedElement() else { return nil }
        let text: String? = axAttr(el, kAXValueAttribute) ?? axAttr(el, kAXSelectedTextAttribute)
        guard let text, !text.isEmpty else { return nil }
        return String(text.suffix(1000))
    }

    // MARK: - Clipboard fallback (Electron/web apps)

    private static func selectedViaClipboard() async -> String? {
        let pb = NSPasteboard.general
        let savedCount = pb.changeCount
        let snapshot = ClipboardSnapshot.save()

        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        try? await Task.sleep(nanoseconds: 100_000_000)

        guard pb.changeCount != savedCount,
              let text = pb.string(forType: .string), !text.isEmpty else {
            return nil
        }

        snapshot.restore()
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
