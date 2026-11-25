import AppKit
import Combine
import QuartzCore

/// One transparent, click-through overlay window's content view.
///
/// Static artwork is rendered once with Core Graphics. Every bulb is an
/// assembly of three layers (container, dark glass, lit glass). The lit glass
/// keeps its looping Core Animation opacity animation; the container is rotated
/// by a small damped pendulum simulation while the cursor is nearby.
final class LightsOverlayView: NSView {
    private struct BulbRuntime {
        let container: CALayer
        let darkGlass: CALayer
        let litGlass: CALayer
        var angle: Double = 0
        var angularVelocity: Double = 0
        var targetAngle: Double = 0
    }

    private let settings: Settings
    private let renderer = LightsRenderer()
    private let baseLayer = CALayer()
    private var bulbRuntimes: [BulbRuntime] = []
    private var cancellables = Set<AnyCancellable>()

    private var builtSize: CGSize = .zero
    private var builtScale: CGFloat = 0

    private var physicsLink: CADisplayLink?
    private var lastPhysicsTimestamp: CFTimeInterval = 0

    private static let mouseRadius: CGFloat = 80
    private static let maxSwingAngle = 40.0 * Double.pi / 180.0
    private static let springConstant = 38.0
    private static let perFrameDamping = 0.94
    private static let impulseScale = 0.015
    private static let maxImpulse = 2.0

    /// Set to false while the overlays are hidden so no layers animate.
    var isAnimating = true {
        didSet {
            guard oldValue != isAnimating else { return }
            applyAnimations()
            if !isAnimating {
                stopMousePhysics(reset: true)
            }
        }
    }

    init(settings: Settings) {
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        observeSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMousePhysics(reset: true)
            physicsLink?.invalidate()
            physicsLink = nil
        } else {
            rebuild()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize != builtSize {
            rebuild()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if (window?.backingScaleFactor ?? 1) != builtScale {
            rebuild()
        }
    }

    deinit {
        physicsLink?.invalidate()
    }

    // MARK: - Settings

    private func observeSettings() {
        settings.$theme
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        settings.$glow
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshBulbImages() }
            .store(in: &cancellables)

        settings.$mode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAnimations() }
            .store(in: &cancellables)

        settings.$speed
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAnimations() }
            .store(in: &cancellables)
    }

    // MARK: - Layers

    private func rebuild() {
        guard let window, bounds.width > 1, bounds.height > 1 else { return }

        stopMousePhysics(reset: true)

        let scale = window.backingScaleFactor
        let size = bounds.size
        builtSize = size
        builtScale = scale

        renderer.prepare(width: size.width, theme: settings.theme)

        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        bulbRuntimes.removeAll(keepingCapacity: true)

        baseLayer.frame = CGRect(origin: .zero, size: size)
        baseLayer.contents = renderer.makeBaseImage(size: size, scale: scale, theme: settings.theme)
        baseLayer.contentsGravity = .resize
        baseLayer.contentsScale = scale
        baseLayer.minificationFilter = .linear
        baseLayer.magnificationFilter = .linear
        layer?.addSublayer(baseLayer)

        let diameter = renderer.bulbSpriteDiameter(glow: settings.glow)
        let anchorY = (diameter / 2 + LightsRenderer.bulbHalfHeight) / diameter
        var darkImages: [Int: CGImage] = [:]
        var litImages: [Int: CGImage] = [:]

        for bulb in renderer.bulbs {
            let container = CALayer()
            container.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            container.anchorPoint = CGPoint(x: 0.5, y: anchorY)
            container.position = CGPoint(
                x: bulb.x,
                y: size.height - (bulb.wireY + LightsRenderer.bulbPivotOffsetFromWireY)
            )
            container.allowsEdgeAntialiasing = true

            let darkImage: CGImage?
            if let cached = darkImages[bulb.colorIndex] {
                darkImage = cached
            } else {
                darkImage = renderer.makeBulbImage(
                    colorIndex: bulb.colorIndex,
                    glow: settings.glow,
                    scale: scale,
                    theme: settings.theme,
                    artwork: .unlit
                )
                darkImages[bulb.colorIndex] = darkImage
            }

            let litImage: CGImage?
            if let cached = litImages[bulb.colorIndex] {
                litImage = cached
            } else {
                litImage = renderer.makeBulbImage(
                    colorIndex: bulb.colorIndex,
                    glow: settings.glow,
                    scale: scale,
                    theme: settings.theme,
                    artwork: .lit
                )
                litImages[bulb.colorIndex] = litImage
            }

            let darkGlass = makeBulbLayer(contents: darkImage, size: diameter, scale: scale)
            let litGlass = makeBulbLayer(contents: litImage, size: diameter, scale: scale)
            darkGlass.opacity = 1

            container.addSublayer(darkGlass)
            container.addSublayer(litGlass)
            layer?.addSublayer(container)

            bulbRuntimes.append(
                BulbRuntime(
                    container: container,
                    darkGlass: darkGlass,
                    litGlass: litGlass
                )
            )
        }

        applyAnimations()
        applyPhysicsTransforms()
    }

    private func makeBulbLayer(contents: CGImage?, size: CGFloat, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.contents = contents
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        layer.minificationFilter = .linear
        layer.magnificationFilter = .linear
        layer.isOpaque = false
        return layer
    }

    /// Regenerates the bulb artwork when the glow slider moves, keeping the
    /// layers (and any current swing angle) intact.
    private func refreshBulbImages() {
        guard
            let window,
            bulbRuntimes.count == renderer.bulbs.count,
            builtSize.width > 1
        else { return }

        let scale = window.backingScaleFactor
        let diameter = renderer.bulbSpriteDiameter(glow: settings.glow)
        let anchorY = (diameter / 2 + LightsRenderer.bulbHalfHeight) / diameter
        let layerFrame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        var darkImages: [Int: CGImage] = [:]
        var litImages: [Int: CGImage] = [:]

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (index, runtime) in bulbRuntimes.enumerated() {
            let bulb = renderer.bulbs[index]

            runtime.container.bounds = layerFrame
            runtime.container.anchorPoint = CGPoint(x: 0.5, y: anchorY)
            runtime.container.position = CGPoint(
                x: bulb.x,
                y: bounds.height - (bulb.wireY + LightsRenderer.bulbPivotOffsetFromWireY)
            )
            runtime.darkGlass.frame = layerFrame
            runtime.litGlass.frame = layerFrame

            if let cached = darkImages[bulb.colorIndex] {
                runtime.darkGlass.contents = cached
            } else {
                let image = renderer.makeBulbImage(
                    colorIndex: bulb.colorIndex,
                    glow: settings.glow,
                    scale: scale,
                    theme: settings.theme,
                    artwork: .unlit
                )
                darkImages[bulb.colorIndex] = image
                runtime.darkGlass.contents = image
            }

            if let cached = litImages[bulb.colorIndex] {
                runtime.litGlass.contents = cached
            } else {
                let image = renderer.makeBulbImage(
                    colorIndex: bulb.colorIndex,
                    glow: settings.glow,
                    scale: scale,
                    theme: settings.theme,
                    artwork: .lit
                )
                litImages[bulb.colorIndex] = image
                runtime.litGlass.contents = image
            }
        }

        CATransaction.commit()
        applyPhysicsTransforms()
    }

    private func applyAnimations() {
        guard bulbRuntimes.count == renderer.bulbs.count else { return }
        let shouldAnimate = isAnimating

        for (index, runtime) in bulbRuntimes.enumerated() {
            runtime.litGlass.removeAnimation(forKey: "festive.brightness")

            guard shouldAnimate else {
                runtime.litGlass.opacity = 1
                continue
            }

            let bulb = renderer.bulbs[index]
            let specification = LightAnimator.specification(
                mode: settings.mode,
                index: index,
                count: renderer.bulbs.count,
                phase: bulb.phase,
                rate: bulb.rate,
                speed: settings.speed
            )

            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = specification.values
            animation.duration = specification.duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false

            runtime.litGlass.opacity = specification.values.first?.floatValue ?? 1
            runtime.litGlass.add(animation, forKey: "festive.brightness")
        }
    }

    // MARK: - Mouse sway

    /// Called by `OverlayController` for each global mouse move. `point` is in
    /// this view's (non-flipped, y-up) coordinate space.
    func handlePointerMove(at point: CGPoint, deltaX: CGFloat, horizontalVelocity: CGFloat) {
        guard settings.isOn, settings.mouseSway, isAnimating, window != nil else { return }
        guard !bulbRuntimes.isEmpty else { return }
        guard
            point.x > -Self.mouseRadius,
            point.x < bounds.width + Self.mouseRadius,
            point.y > -Self.mouseRadius,
            point.y < bounds.height + Self.mouseRadius
        else { return }

        let dx = Double(min(max(deltaX, -250), 250))
        guard abs(dx) > 0.05 else { return }

        let speedBoost = min(1.6, max(0.5, abs(Double(horizontalVelocity)) / 600.0))
        var moved = false

        for index in bulbRuntimes.indices {
            let bulb = renderer.bulbs[index]
            let runtime = bulbRuntimes[index]

            let pivotY = bounds.height - (bulb.wireY + LightsRenderer.bulbPivotOffsetFromWireY)
            let bodyX = bulb.x + CGFloat(sin(runtime.angle)) * LightsRenderer.bulbHalfHeight
            let bodyY = pivotY - CGFloat(cos(runtime.angle)) * LightsRenderer.bulbHalfHeight
            let offsetX = point.x - bodyX
            let offsetY = point.y - bodyY
            let distance = (offsetX * offsetX + offsetY * offsetY).squareRoot()
            guard distance < Self.mouseRadius else { continue }

            let normalized = max(0, 1 - distance / Self.mouseRadius)
            let falloff = pow(Double(normalized), 1.5)
            let impulse = min(
                max(dx * Self.impulseScale * falloff * speedBoost, -Self.maxImpulse),
                Self.maxImpulse
            )
            guard abs(impulse) > 0.0005 else { continue }

            bulbRuntimes[index].angularVelocity += impulse
            bulbRuntimes[index].targetAngle = 0
            moved = true
        }

        if moved {
            startPhysics()
        }
    }

    /// Stops the pendulum simulation. Called when the lights are hidden or the
    /// mouse-sway setting is turned off.
    func stopMousePhysics(reset: Bool = true) {
        physicsLink?.isPaused = true
        lastPhysicsTimestamp = 0
        guard reset else { return }

        for index in bulbRuntimes.indices {
            bulbRuntimes[index].angle = 0
            bulbRuntimes[index].angularVelocity = 0
            bulbRuntimes[index].targetAngle = 0
        }
        applyPhysicsTransforms()
    }

    private func startPhysics() {
        guard window != nil else { return }

        if physicsLink == nil {
            let link = displayLink(target: self, selector: #selector(stepPhysics(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            physicsLink = link
        }

        let wasPaused = physicsLink?.isPaused ?? true
        physicsLink?.isPaused = false
        if wasPaused {
            lastPhysicsTimestamp = 0
        }
    }

    @objc private func stepPhysics(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastPhysicsTimestamp == 0 {
            lastPhysicsTimestamp = now
            return
        }

        let dt = min(max(now - lastPhysicsTimestamp, 0), 1.0 / 30.0)
        lastPhysicsTimestamp = now
        guard dt > 0 else { return }

        var anyMotion = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for index in bulbRuntimes.indices {
            var runtime = bulbRuntimes[index]

            let spring = -Self.springConstant * (runtime.angle - runtime.targetAngle)
            runtime.angularVelocity += spring * dt
            runtime.angularVelocity *= pow(Self.perFrameDamping, dt * 60.0)
            runtime.angle += runtime.angularVelocity * dt

            if runtime.angle > Self.maxSwingAngle {
                runtime.angle = Self.maxSwingAngle
                runtime.angularVelocity = min(0, runtime.angularVelocity)
            } else if runtime.angle < -Self.maxSwingAngle {
                runtime.angle = -Self.maxSwingAngle
                runtime.angularVelocity = max(0, runtime.angularVelocity)
            }

            if abs(runtime.angle) < 0.0004, abs(runtime.angularVelocity) < 0.0015 {
                runtime.angle = 0
                runtime.angularVelocity = 0
            } else {
                anyMotion = true
            }

            runtime.container.transform = CATransform3DMakeRotation(CGFloat(runtime.angle), 0, 0, 1)
            bulbRuntimes[index] = runtime
        }

        CATransaction.commit()

        if !anyMotion {
            physicsLink?.isPaused = true
            lastPhysicsTimestamp = 0
        }
    }

    private func applyPhysicsTransforms() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for runtime in bulbRuntimes {
            runtime.container.transform = CATransform3DMakeRotation(CGFloat(runtime.angle), 0, 0, 1)
        }
        CATransaction.commit()
    }
}
