import AppKit
import Combine
import CoreGraphics

/// Owns the movable Christmas tree window. The tree is a small, interactive
/// desktop object: it sits above desktop icons (or above apps in Always on Top
/// mode), can be dragged anywhere on screen, and remembers its position.
final class ChristmasTreeController {
    private let settings: Settings
    private let defaults: UserDefaults
    private var window: TreeWindow?
    private var treeView: ChristmasTreeView?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    private var dragOffset = CGPoint.zero
    private let treeSize = NSSize(width: 250, height: 350)
    private let edgeInset: CGFloat = 8

    private enum Keys {
        static let originX = "festiveLights.treeOriginX"
        static let originY = "festiveLights.treeOriginY"
    }

    init(settings: Settings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
    }

    // MARK: - Lifecycle

    func start() {
        applyVisibility(settings.showTree)

        settings.$showTree
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.applyVisibility(visible)
            }
            .store(in: &cancellables)

        settings.$layering
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyWindowLevel()
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.repositionForScreenChange()
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.orderFrontIfVisible()
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.orderFrontIfVisible()
                self?.repositionForScreenChange()
            }
        )
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        cancellables.removeAll()

        window?.orderOut(nil)
        window?.close()
        window = nil
        treeView = nil
    }

    deinit {
        stop()
    }

    // MARK: - Visibility and level

    private func applyVisibility(_ visible: Bool) {
        if visible {
            let window = ensureWindow()
            applyWindowLevel()
            let origin = clampedOrigin(window.frame.origin)
            window.setFrameOrigin(origin)
            window.orderFrontRegardless()
            treeView?.needsDisplay = true
        } else {
            window?.orderOut(nil)
        }
    }

    private func orderFrontIfVisible() {
        guard settings.showTree else { return }
        window?.orderFrontRegardless()
    }

    private var windowLevel: NSWindow.Level {
        switch settings.layering {
        case .desktop:
            // Above the desktop icons, below normal app windows.
            return NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            )
        case .alwaysOnTop:
            return .statusBar
        }
    }

    private func applyWindowLevel() {
        guard let window else { return }
        window.level = windowLevel
        if settings.showTree {
            window.orderFrontRegardless()
        }
    }

    // MARK: - Window

    private func ensureWindow() -> TreeWindow {
        if let window { return window }

        let origin = initialOrigin()
        let view = ChristmasTreeView(settings: settings)
        view.onDragBegan = { [weak self] point in
            self?.beginDrag(at: point)
        }
        view.onDragMoved = { [weak self] point in
            self?.drag(to: point)
        }
        view.onDragEnded = { [weak self] in
            self?.endDrag()
        }

        let window = TreeWindow(
            contentRect: NSRect(origin: origin, size: treeSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = windowLevel
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.animationBehavior = .none
        window.acceptsMouseMovedEvents = true
        window.isExcludedFromWindowsMenu = true
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = true
        window.worksWhenModal = true
        window.contentView = view
        window.setFrameOrigin(origin)

        self.window = window
        self.treeView = view
        return window
    }

    // MARK: - Position

    private func initialOrigin() -> CGPoint {
        if
            let x = defaults.object(forKey: Keys.originX) as? Double,
            let y = defaults.object(forKey: Keys.originY) as? Double
        {
            return clampedOrigin(CGPoint(x: x, y: y))
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            return CGPoint(x: 100, y: 100)
        }
        // Keep the tree above the train's track and tunnel portals.
        let trainClearance = TrainView.preferredHeight + 24
        return clampedOrigin(
            CGPoint(
                x: visible.maxX - treeSize.width - 36,
                y: visible.minY + 30 + trainClearance
            )
        )
    }

    private func clampedOrigin(_ origin: CGPoint, near reference: CGPoint? = nil) -> CGPoint {
        let frame = NSRect(origin: origin, size: treeSize)
        let anchor = reference ?? CGPoint(x: frame.midX, y: frame.midY)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
            ?? NSScreen.screens.max {
                intersectionArea($0.frame, frame) < intersectionArea($1.frame, frame)
            }
            ?? NSScreen.main

        guard let visible = screen?.visibleFrame else { return origin }

        let minX = visible.minX + edgeInset
        let maxX = max(minX, visible.maxX - treeSize.width - edgeInset)
        let minY = visible.minY + edgeInset
        let maxY = max(minY, visible.maxY - treeSize.height - edgeInset)

        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func saveOrigin(_ origin: CGPoint) {
        defaults.set(Double(origin.x), forKey: Keys.originX)
        defaults.set(Double(origin.y), forKey: Keys.originY)
    }

    // MARK: - Dragging

    private func beginDrag(at screenPoint: CGPoint) {
        guard let window else { return }
        dragOffset = CGPoint(
            x: screenPoint.x - window.frame.minX,
            y: screenPoint.y - window.frame.minY
        )
        window.orderFrontRegardless()
    }

    private func drag(to screenPoint: CGPoint) {
        guard let window else { return }
        let desired = CGPoint(
            x: screenPoint.x - dragOffset.x,
            y: screenPoint.y - dragOffset.y
        )
        window.setFrameOrigin(clampedOrigin(desired, near: screenPoint))
    }

    private func endDrag() {
        guard let window else { return }
        saveOrigin(window.frame.origin)
    }

    /// Back to the bottom-right of the current main display.
    func resetPosition() {
        let origin = defaultOrigin()
        if let window {
            window.setFrameOrigin(origin)
            if settings.showTree {
                window.orderFrontRegardless()
            }
        }
        saveOrigin(origin)
    }

    private func repositionForScreenChange() {
        guard settings.showTree, let window else { return }
        let origin = clampedOrigin(window.frame.origin)
        window.setFrameOrigin(origin)
        saveOrigin(origin)
        window.orderFrontRegardless()
    }
}

// MARK: - Window

final class TreeWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
