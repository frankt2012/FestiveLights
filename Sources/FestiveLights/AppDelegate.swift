import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let hotKey = HotKeyManager()
    private var overlayController: OverlayController?
    private var trainController: TrainController?
    private var treeController: ChristmasTreeController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The activation policy is set in main.swift before the run loop starts.
        guard !terminateDuplicateInstanceIfNeeded() else { return }

        let overlays = OverlayController(settings: settings)
        overlayController = overlays
        overlays.start()

        let train = TrainController(settings: settings)
        trainController = train
        train.start()

        let tree = ChristmasTreeController(settings: settings)
        treeController = tree
        tree.start()

        statusItemController = StatusItemController(
            settings: settings,
            onResetTree: { [weak self] in
                self?.treeController?.resetPosition()
            }
        )

        hotKey.onToggle = { [weak self] in
            guard let self else { return }
            self.settings.isOn.toggle()
        }
        hotKey.onShowPanel = { [weak self] in
            self?.statusItemController?.showPanel()
        }
        hotKey.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController?.stop()
        trainController?.stop()
        treeController?.stop()
        hotKey.unregister()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Two copies of a menu bar agent compete for the same status item slot and
    /// can leave the newer copy with an invisible item, so only allow one.
    private func terminateDuplicateInstanceIfNeeded() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let duplicates = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard !duplicates.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }
}
