import AppKit
import Combine
import CoreGraphics

/// Full-width, click-through train overlays at the bottom of every display.
final class TrainController {
    private let settings: Settings
    private var windows: [CGDirectDisplayID: TrainWindow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var pendingRefresh: DispatchWorkItem?

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        refreshWindows()

        settings.$showTrain
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
                self?.applyLevels()
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
                self?.scheduleRefresh()
                self?.orderFrontIfVisible()
            }
        )
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        cancellables.removeAll()

        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    deinit {
        stop()
    }

    // MARK: - Windows

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshWindows()
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func refreshWindows() {
        guard settings.showTrain else { return }

        var seen = Set<CGDirectDisplayID>()
        for (index, screen) in NSScreen.screens.enumerated() {
            let id = displayID(for: screen, fallbackIndex: index)
            seen.insert(id)

            let frame = NSRect(
                x: screen.frame.minX,
                y: screen.visibleFrame.minY,
                width: screen.frame.width,
                height: TrainView.preferredHeight
            )

            if let window = windows[id] {
                if window.frame != frame {
                    window.setFrame(frame, display: false)
                }
                window.level = settings.layering.windowLevel
                window.orderFrontRegardless()
            } else {
                let view = TrainView(settings: settings)
                let window = TrainWindow(
                    contentRect: frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.level = settings.layering.windowLevel
                window.collectionBehavior = [
                    .canJoinAllSpaces,
                    .fullScreenAuxiliary,
                    .stationary,
                    .ignoresCycle
                ]
                window.ignoresMouseEvents = true
                window.isMovable = false
                window.isMovableByWindowBackground = false
                window.isReleasedWhenClosed = false
                window.hidesOnDeactivate = false
                window.canHide = false
                window.animationBehavior = .none
                window.acceptsMouseMovedEvents = false
                window.isExcludedFromWindowsMenu = true
                window.contentView = view
                window.setFrame(frame, display: false)
                windows[id] = window
                window.orderFrontRegardless()
            }
        }

        let staleIDs = windows.keys.filter { !seen.contains($0) }
        for id in staleIDs {
            guard let window = windows.removeValue(forKey: id) else { continue }
            window.orderOut(nil)
            window.close()
        }
    }

    private func applyVisibility(_ visible: Bool) {
        if visible {
            refreshWindows()
            for window in windows.values {
                window.orderFrontRegardless()
            }
        } else {
            for window in windows.values {
                window.orderOut(nil)
            }
        }
    }

    private func applyLevels() {
        for window in windows.values {
            window.level = settings.layering.windowLevel
            if settings.showTrain {
                window.orderFrontRegardless()
            }
        }
    }

    private func orderFrontIfVisible() {
        guard settings.showTrain else { return }
        for window in windows.values {
            window.orderFrontRegardless()
        }
    }

    private func displayID(for screen: NSScreen, fallbackIndex: Int) -> CGDirectDisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return CGDirectDisplayID(20_000 + fallbackIndex)
    }
}

final class TrainWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
