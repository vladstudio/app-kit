import AppKit

/// Checks GitHub releases for updates and prompts the user.
public enum UpdateChecker {
    /// Check for updates from a GitHub repo.
    /// - Parameters:
    ///   - repo: GitHub repo path, e.g. "vladstudio/sten"
    ///   - appName: Display name for dialogs
    ///   - manual: If true, shows "up to date" when current. If false, silent when current.
    public static func check(repo: String, appName: String, manual: Bool = false) {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  assets.contains(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })
            else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            DispatchQueue.main.async {
                if latest.compare(current, options: .numeric) == .orderedDescending {
                    promptUpdate(repo: repo, appName: appName, version: latest)
                } else if manual {
                    showUpToDate(appName: appName, current: current)
                }
            }
        }.resume()
    }

    @MainActor private static func showUpToDate(appName: String, current: String) {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "\(appName) \(current) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor private static func promptUpdate(repo: String, appName: String, version: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "\(appName) \(version) is ready to download and install."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let script = "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/install.sh | bash"
            let osa = "tell app \"Terminal\" to do script \"\(script)\""
            Process.launchedProcess(launchPath: "/usr/bin/osascript", arguments: ["-e", osa])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        }
    }
}
