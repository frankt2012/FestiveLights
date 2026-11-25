import AppKit
import Combine
import ServiceManagement

/// Offers "Launch at Login" using SMAppService where macOS supports it for
/// this app location, and falls back to a user LaunchAgent for local builds
/// (for example an app run from an external volume).
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusDetail = "Off."
    @Published private(set) var errorMessage: String?

    private let launchAgentLabel = "com.festivelights.app"

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    private var hasLaunchAgent: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
            statusDetail = "Starts automatically when you log in."

        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
            statusDetail = "Approve FestiveLights in System Settings → Login Items."

        case .notRegistered, .notFound:
            if hasLaunchAgent {
                isEnabled = true
                requiresApproval = false
                statusDetail = "Starts automatically when you log in (login agent)."
            } else {
                isEnabled = false
                requiresApproval = false
                statusDetail = "Off."
            }

        @unknown default:
            isEnabled = hasLaunchAgent
            requiresApproval = false
            statusDetail = hasLaunchAgent
                ? "Starts automatically when you log in (login agent)."
                : "Off."
        }

        if let errorMessage, !isEnabled {
            statusDetail = errorMessage
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil

        if enabled {
            registerNativeOrAgent()
        } else {
            unregisterAll()
        }

        refresh()
    }

    private func registerNativeOrAgent() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            // The native login item is unavailable for some app locations;
            // fall through to the LaunchAgent path below.
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            removeLaunchAgent()
        case .notRegistered, .notFound:
            installLaunchAgent()
        @unknown default:
            installLaunchAgent()
        }
    }

    private func unregisterAll() {
        try? SMAppService.mainApp.unregister()
        removeLaunchAgent()
    }

    private func installLaunchAgent() {
        let directory = launchAgentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let propertyList: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: propertyList,
                format: .xml,
                options: 0
            )
            try data.write(to: launchAgentURL, options: .atomic)
        } catch {
            errorMessage = "Couldn't install the login agent: \(error.localizedDescription)"
            return
        }

        runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
    }

    private func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
        runLaunchctl(["bootout", "gui/\(getuid())/\(launchAgentLabel)"])
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
