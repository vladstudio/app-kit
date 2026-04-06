import ServiceManagement

public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func toggle() {
        try? isEnabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
    }

    public static func enable() {
        try? SMAppService.mainApp.register()
    }

    public static func disable() {
        try? SMAppService.mainApp.unregister()
    }

    /// Enable on first launch, then respect user's choice.
    public static func enableOnFirstLaunch(key: String = "loginItemConfigured") {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        enable()
    }
}
