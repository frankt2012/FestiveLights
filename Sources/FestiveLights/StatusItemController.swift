import AppKit
import Combine
import SwiftUI

/// Owns the menu bar status item, its SwiftUI popover, and the right-click
/// menu with quick access to the same settings.
final class StatusItemController: NSObject {
    private let settings: Settings
    private let onResetTree: () -> Void
    private let loginManager = LoginItemManager()
    private let updateChecker = UpdateChecker()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings, onResetTree: @escaping () -> Void) {
        self.settings = settings
        self.onResetTree = onResetTree
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configurePopover()
        observeSettings()
    }

    deinit {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "FestiveLights"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("FestiveLights")
        button.toolTip = "FestiveLights · \(HotKeyManager.toggleShortcut) toggles · \(HotKeyManager.panelShortcut) opens the panel"
        statusItem.length = 26
        updateIcon()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true

        let root = ControlsView(
            settings: settings,
            onResetTree: onResetTree,
            loginManager: loginManager,
            updateChecker: updateChecker
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 332, height: 740)
    }

    private func observeSettings() {
        settings.$isOn
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        let symbolName = settings.isOn ? "lightbulb.led.fill" : "lightbulb.slash"
        let fallbackName = settings.isOn ? "lightbulb.fill" : "lightbulb"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .semibold)

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FestiveLights")
            ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: "FestiveLights")
        let configured = image?.withSymbolConfiguration(configuration)
        configured?.isTemplate = true

        if let configured {
            statusItem.button?.title = ""
            statusItem.button?.image = configured
            statusItem.button?.imagePosition = .imageOnly
        } else {
            // Should not happen on macOS 14+, but stay reachable regardless.
            statusItem.button?.image = nil
            statusItem.button?.title = "✦"
            statusItem.button?.imagePosition = .noImage
        }
        statusItem.button?.setAccessibilityLabel(settings.isOn ? "FestiveLights, on" : "FestiveLights, off")
    }

    // MARK: - Status item interaction

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Used by the ⌥⌘P global shortcut, including when the menu bar is too
    /// crowded to show the status item.
    func showPanel() {
        guard !popover.isShown else { return }
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()

        let toggleTitle = settings.isOn ? "Turn Lights Off" : "Turn Lights On"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleLights), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let modesItem = NSMenuItem(title: "Animation", action: nil, keyEquivalent: "")
        let modesMenu = NSMenu()
        for mode in LightMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            modesMenu.addItem(item)
        }
        modesItem.submenu = modesMenu
        menu.addItem(modesItem)

        let themesItem = NSMenuItem(title: "Color Theme", action: nil, keyEquivalent: "")
        let themesMenu = NSMenu()
        for theme in LightTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.state = settings.theme == theme ? .on : .off
            themesMenu.addItem(item)
        }
        themesItem.submenu = themesMenu
        menu.addItem(themesItem)

        let layeringItem = NSMenuItem(title: "Layering", action: nil, keyEquivalent: "")
        let layeringMenu = NSMenu()
        for layering in OverlayLayering.allCases {
            let item = NSMenuItem(title: layering.title, action: #selector(selectLayering(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layering.rawValue
            item.state = settings.layering == layering ? .on : .off
            layeringMenu.addItem(item)
        }
        layeringItem.submenu = layeringMenu
        menu.addItem(layeringItem)

        let swayItem = NSMenuItem(
            title: "Interactive Mouse Sway",
            action: #selector(toggleMouseSway),
            keyEquivalent: ""
        )
        swayItem.target = self
        swayItem.state = settings.mouseSway ? .on : .off
        menu.addItem(swayItem)

        let treeItem = NSMenuItem(
            title: "Show Christmas Tree",
            action: #selector(toggleTree),
            keyEquivalent: ""
        )
        treeItem.target = self
        treeItem.state = settings.showTree ? .on : .off
        menu.addItem(treeItem)

        let resetTreeItem = NSMenuItem(
            title: "Reset Tree Position",
            action: #selector(resetTreePosition),
            keyEquivalent: ""
        )
        resetTreeItem.target = self
        menu.addItem(resetTreeItem)

        let trainItem = NSMenuItem(
            title: "Show Steam Train",
            action: #selector(toggleTrain),
            keyEquivalent: ""
        )
        trainItem.target = self
        trainItem.state = settings.showTrain ? .on : .off
        menu.addItem(trainItem)

        let trainCarsItem = NSMenuItem(title: "Train Cars", action: nil, keyEquivalent: "")
        let trainCarsMenu = NSMenu()
        for carType in TrainCarType.allCases {
            let item = NSMenuItem(
                title: carType.title,
                action: #selector(selectTrainCarType(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = carType.rawValue
            item.state = settings.trainCarType == carType ? .on : .off
            trainCarsMenu.addItem(item)
        }
        trainCarsItem.submenu = trainCarsMenu
        menu.addItem(trainCarsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit FestiveLights", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    // MARK: - Actions

    @objc private func toggleLights() {
        settings.isOn.toggle()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = LightMode(rawValue: raw)
        else { return }
        settings.mode = mode
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let theme = LightTheme(rawValue: raw)
        else { return }
        settings.theme = theme
    }

    @objc private func selectLayering(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let layering = OverlayLayering(rawValue: raw)
        else { return }
        settings.layering = layering
    }

    @objc private func toggleMouseSway() {
        settings.mouseSway.toggle()
    }

    @objc private func toggleTree() {
        settings.showTree.toggle()
    }

    @objc private func resetTreePosition() {
        onResetTree()
    }

    @objc private func toggleTrain() {
        settings.showTrain.toggle()
    }

    @objc private func selectTrainCarType(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let carType = TrainCarType(rawValue: raw)
        else { return }
        settings.trainCarType = carType
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
