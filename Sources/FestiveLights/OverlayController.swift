import AppKit
import Combine
import CoreGraphics
import QuartzCore

/// Creates and maintains one borderless overlay window per connected display.
final class OverlayController {
    private let settings: Settings
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var pendingRefresh: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    private var mouseMonitor: Any?
    private var lastMouseLocation: CGPoint?
    private var lastMouseTime: TimeInterval = 0

    private let overlayHeight: CGFloat = 62

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        refreshWindows()
        updateMouseTracking()

        settings.$isOn
            .removeDuplicates()
            .dropFirst() // The initial value is already covered by refreshWindows().
            .receive(on: RunLoop.main)
            .sink { [weak self] isOn in
                self?.applyVisibility(isOn)
                self?.updateMouseTracking()
            }
            .store(in: &cancellables)

        settings.$mouseSway
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMouseTracking()
            }
            .store(in: &cancellables)

        settings.$layering
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] layering in
                self?.applyLayering(layering)
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRefresh()
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRefresh()
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.bringToFront()
            }
        )
    }

    deinit {
        stop()
    }

    /// Tears down the global event monitor and overlay windows. Called when the
    /// app terminates as well as from `deinit`.
    func stop() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        lastMouseLocation = nil

        pendingRefresh?.cancel()
        pendingRefresh = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        cancellables.removeAll()

        for window in windows.values {
            (window.contentView as? LightsOverlayView)?.stopMousePhysics(reset: true)
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    // MARK: - Window management

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshWindows()
        }
        pendingRefresh = work
        // Display reconfiguration can post several notifications in a burst.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func refreshWindows() {
        var activeIDs = Set<CGDirectDisplayID>()

        for (offset, screen) in NSScreen.screens.enumerated() {
            let id = displayID(for: screen, fallbackIndex: offset)
            activeIDs.insert(id)
            let frame = overlayFrame(for: screen)

            if let window = windows[id] {
                if window.frame != frame {
                    window.setFrame(frame, display: true)
                }
                window.level = settings.layering.windowLevel
                if settings.isOn {
                    window.orderFrontRegardless()
                }
            } else {
                let view = LightsOverlayView(settings: settings)
                view.isAnimating = settings.isOn
                let window = OverlayWindow(frame: frame, view: view, layering: settings.layering)
                window.alphaValue = settings.isOn ? 1 : 0
                windows[id] = window
                if settings.isOn {
                    window.orderFrontRegardless()
                }
            }
        }

        let staleIDs = windows.keys.filter { !activeIDs.contains($0) }
        for id in staleIDs {
            guard let window = windows.removeValue(forKey: id) else { continue }
            if let view = window.contentView as? LightsOverlayView {
                view.isAnimating = false
            }
            window.orderOut(nil)
            window.close()
        }
    }

    private func applyVisibility(_ isOn: Bool) {
        if isOn {
            refreshWindows()
            for window in windows.values {
                window.alphaValue = 0
                window.orderFrontRegardless()
                (window.contentView as? LightsOverlayView)?.isAnimating = true
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for window in self.windows.values {
                    window.animator().alphaValue = 1
                }
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                for window in self.windows.values {
                    window.animator().alphaValue = 0
                }
            } completionHandler: { [weak self] in
                guard let self, !self.settings.isOn else { return }
                for window in self.windows.values {
                    window.orderOut(nil)
                    (window.contentView as? LightsOverlayView)?.isAnimating = false
                }
            }
        }
    }

    private func bringToFront() {
        guard settings.isOn else { return }
        for window in windows.values {
            window.orderFrontRegardless()
        }
    }

    private func applyLayering(_ layering: OverlayLayering) {
        for window in windows.values {
            window.level = layering.windowLevel
            if settings.isOn {
                window.orderFrontRegardless()
            }
        }
    }

    // MARK: - Global mouse tracking

    private func updateMouseTracking() {
        let shouldTrack = settings.isOn && settings.mouseSway

        if shouldTrack {
            guard mouseMonitor == nil else { return }

            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] _ in
                self?.handleGlobalMouseMove()
            }

            lastMouseLocation = NSEvent.mouseLocation
            lastMouseTime = ProcessInfo.processInfo.systemUptime
        } else {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            lastMouseLocation = nil

            for window in windows.values {
                (window.contentView as? LightsOverlayView)?.stopMousePhysics(reset: true)
            }
        }
    }

    private func handleGlobalMouseMove() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleGlobalMouseMove()
            }
            return
        }

        guard settings.isOn, settings.mouseSway else { return }

        let location = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime

        guard let previous = lastMouseLocation else {
            lastMouseLocation = location
            lastMouseTime = now
            return
        }

        let dt = max(now - lastMouseTime, 1.0 / 240.0)
        let deltaX = location.x - previous.x
        let velocityX = deltaX / dt

        lastMouseLocation = location
        lastMouseTime = now

        guard abs(deltaX) > 0.05 else { return }

        for window in windows.values {
            guard
                window.isVisible,
                let view = window.contentView as? LightsOverlayView
            else { continue }

            let windowPoint = window.convertPoint(fromScreen: location)
            let localPoint = view.convert(windowPoint, from: nil)
            view.handlePointerMove(
                at: localPoint,
                deltaX: deltaX,
                horizontalVelocity: velocityX
            )
        }
    }

    private func overlayFrame(for screen: NSScreen) -> NSRect {
        // visibleFrame.maxY sits just under the menu bar and already accounts
        // for the camera notch on notched MacBooks.
        let top = screen.visibleFrame.maxY
        let y = max(screen.frame.minY, top - overlayHeight)
        return NSRect(
            x: screen.frame.minX,
            y: y,
            width: screen.frame.width,
            height: overlayHeight
        )
    }

    private func displayID(for screen: NSScreen, fallbackIndex: Int) -> CGDirectDisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return CGDirectDisplayID(10_000 + fallbackIndex)
    }
}

// MARK: - Overlay window

final class OverlayWindow: NSWindow {
    init(frame: NSRect, view: NSView, layering: OverlayLayering) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = layering.windowLevel
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false
        animationBehavior = .none
        acceptsMouseMovedEvents = false

        contentView = view
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Window levels

extension OverlayLayering {
    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop:
            // One step above the wallpaper, below the Finder icons, Dock and
            // normal application windows.
            return NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
            )
        case .alwaysOnTop:
            // The original always-on-top behavior: above apps and full-screen
            // windows, but still below the menu bar and the app's popover.
            return .statusBar
        }
    }
}
