import Foundation

public enum ConfigDir {
    /// Returns the config directory for the given app name.
    /// Honors `$XDG_CONFIG_HOME`, falls back to `~/.config`.
    /// Creates the directory if it doesn't exist.
    public static func url(for appName: String) -> URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let dir = base.appendingPathComponent(appName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Migrates a file from an old location to the new config dir.
    /// No-op if source doesn't exist or destination already exists.
    public static func migrate(from oldPath: String, to appName: String, fileName: String) {
        let oldURL = URL(fileURLWithPath: (oldPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return }

        let destURL = url(for: appName).appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: destURL.path) else { return }
        try? FileManager.default.moveItem(at: oldURL, to: destURL)
    }

    /// Migrates a directory's contents from old location into the config dir.
    /// No-op if source doesn't exist. Skips files that already exist at destination.
    public static func migrateDirectory(from oldPath: String, to appName: String) {
        let oldURL = URL(fileURLWithPath: (oldPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return }

        let dir = url(for: appName)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: oldURL.path)) ?? []
        for file in contents {
            let src = oldURL.appendingPathComponent(file)
            let dst = dir.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.moveItem(at: src, to: dst)
            }
        }
        // Remove old directory if now empty
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: oldURL.path)) ?? []
        if remaining.isEmpty { try? FileManager.default.removeItem(at: oldURL) }
    }
}
