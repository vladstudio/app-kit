import AppKit
import AVFoundation
import IOKit.hid

public enum Permission: Sendable {
    case accessibility
    case inputMonitoring
    case microphone
    case screenRecording
}

public enum Permissions {
    // MARK: - Check

    public static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .inputMonitoring:
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: - Request

    public static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(
                ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            )
        case .inputMonitoring:
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - Open System Settings

    public static func openSettings(_ permission: Permission) {
        let url: String
        switch permission {
        case .accessibility:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .microphone:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .screenRecording:
            url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        NSWorkspace.shared.open(URL(string: url)!)
    }

    // MARK: - Polling

    /// Polls until all permissions are granted, then calls `onGranted`.
    /// Returns the timer so the caller can invalidate it.
    @discardableResult
    public static func pollUntilGranted(
        _ permissions: [Permission],
        interval: TimeInterval = 2,
        onStatus: (@Sendable (_ granted: [Permission], _ missing: [Permission]) -> Void)? = nil,
        onGranted: @Sendable @escaping () -> Void
    ) -> Timer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            let granted = permissions.filter { isGranted($0) }
            let missing = permissions.filter { !isGranted($0) }
            onStatus?(granted, missing)
            if missing.isEmpty {
                timer.invalidate()
                onGranted()
            }
        }
    }
}
