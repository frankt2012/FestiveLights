import AppKit
import Combine
import CoreGraphics

/// A transparent, interactive Christmas tree. The tree is drawn with Core
/// Graphics once per theme change; dragging is handled by the controller via
/// these closures.
final class ChristmasTreeView: NSView {
    private let settings: Settings

    var onDragBegan: ((CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var isDragging = false
    private var trackingAreaRef: NSTrackingArea?
    private var ornamentLayers: [CALayer] = []
    private var cancellables = Set<AnyCancellable>()
    private var builtSize: CGSize = .zero
    private var builtScale: CGFloat = 0

    private struct Tier {
        let baseY: CGFloat
        let apexY: CGFloat
        let halfWidth: CGFloat
    }

    private struct OrnamentLayout {
        let center: CGPoint
        let radius: CGFloat
    }

    init(settings: Settings) {
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        observeSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        drawTree(in: context, size: bounds.size)
    }

    private func drawTree(in context: CGContext, size: CGSize) {
        let cx = size.width / 2
        let groundY = size.height - 32
        let tiers = treeTiers(for: size)

        let shadowRect = CGRect(x: cx - 78, y: groundY - 8, width: 156, height: 20)
        context.setFillColor(cg(0, 0, 0, 0.16))
        context.fillEllipse(in: shadowRect)
        context.setFillColor(cg(0, 0, 0, 0.10))
        context.fillEllipse(in: CGRect(x: cx - 54, y: groundY - 4, width: 108, height: 14))

        drawTrunk(in: context, cx: cx, groundY: groundY)

        for tier in tiers {
            drawTier(tier, in: context, cx: cx)
        }

        drawGifts(in: context, cx: cx, groundY: groundY)

        drawStar(in: context, center: CGPoint(x: cx, y: 46))

        drawSnowflakes(in: context, size: size)
    }

    // MARK: Tree pieces

    private func drawTrunk(in context: CGContext, cx: CGFloat, groundY: CGFloat) {
        let rect = CGRect(x: cx - 15, y: groundY - 56, width: 30, height: 54)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: 5,
            cornerHeight: 5,
            transform: nil
        )

        context.saveGState()
        context.addPath(path)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [cg(0.43, 0.29, 0.18), cg(0.20, 0.12, 0.07)] as CFArray,
            locations: [0, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: cx, y: rect.minY),
                end: CGPoint(x: cx, y: rect.maxY),
                options: []
            )
        }
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(cg(0.16, 0.09, 0.05, 0.9))
        context.setLineWidth(0.8)
        context.strokePath()

        context.setStrokeColor(cg(0.62, 0.46, 0.30, 0.35))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: cx - 6, y: rect.minY + 8))
        context.addLine(to: CGPoint(x: cx - 7, y: rect.maxY - 6))
        context.strokePath()
    }

    private func tierPath(_ tier: Tier, cx: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - tier.halfWidth, y: tier.baseY))
        path.addCurve(
            to: CGPoint(x: cx, y: tier.apexY),
            control1: CGPoint(x: cx - tier.halfWidth * 0.55, y: tier.baseY - 36),
            control2: CGPoint(x: cx - 22, y: tier.apexY + 42)
        )
        path.addCurve(
            to: CGPoint(x: cx + tier.halfWidth, y: tier.baseY),
            control1: CGPoint(x: cx + 22, y: tier.apexY + 42),
            control2: CGPoint(x: cx + tier.halfWidth * 0.55, y: tier.baseY - 36)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx - tier.halfWidth, y: tier.baseY),
            control: CGPoint(x: cx, y: tier.baseY + 9)
        )
        path.closeSubpath()
        return path
    }

    private func drawTier(_ tier: Tier, in context: CGContext, cx: CGFloat) {
        let path = tierPath(tier, cx: cx)

        context.saveGState()
        context.addPath(path)
        context.clip()

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                cg(0.12, 0.37, 0.215),
                cg(0.055, 0.225, 0.125),
                cg(0.025, 0.115, 0.065)
            ] as CFArray,
            locations: [0, 0.55, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: cx, y: tier.apexY),
                end: CGPoint(x: cx, y: tier.baseY),
                options: []
            )
        }

        // Branch texture inside the tier.
        for index in 0..<3 {
            let y = tier.baseY - 26 - CGFloat(index) * 28
            guard y > tier.apexY + 28 else { break }
            let half = tier.halfWidth * (y - tier.apexY) / (tier.baseY - tier.apexY)
            context.move(to: CGPoint(x: cx - half * 0.76, y: y))
            context.addQuadCurve(
                to: CGPoint(x: cx + half * 0.76, y: y),
                control: CGPoint(x: cx, y: y + 11)
            )
            context.setStrokeColor(cg(0.015, 0.075, 0.04, 0.34))
            context.setLineWidth(1.0)
            context.strokePath()
        }

        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(cg(0.30, 0.58, 0.375, 0.38))
        context.setLineWidth(1.2)
        context.strokePath()

        // Snow catches the upper branches.
        context.move(to: CGPoint(x: cx - tier.halfWidth, y: tier.baseY))
        context.addCurve(
            to: CGPoint(x: cx, y: tier.apexY),
            control1: CGPoint(x: cx - tier.halfWidth * 0.55, y: tier.baseY - 36),
            control2: CGPoint(x: cx - 22, y: tier.apexY + 42)
        )
        context.addCurve(
            to: CGPoint(x: cx + tier.halfWidth, y: tier.baseY),
            control1: CGPoint(x: cx + 22, y: tier.apexY + 42),
            control2: CGPoint(x: cx + tier.halfWidth * 0.55, y: tier.baseY - 36)
        )
        context.setStrokeColor(cg(0.82, 0.94, 0.86, 0.22))
        context.setLineWidth(1.4)
        context.strokePath()

        // Snow-capped tips.
        context.setFillColor(cg(0.88, 0.97, 0.92, 0.55))
        for point in [
            CGPoint(x: cx - tier.halfWidth, y: tier.baseY),
            CGPoint(x: cx + tier.halfWidth, y: tier.baseY),
            CGPoint(x: cx, y: tier.apexY)
        ] {
            context.fillEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
        }
    }

    private func drawGifts(in context: CGContext, cx: CGFloat, groundY: CGFloat) {
        let red = LightColor(red: 0.72, green: 0.12, blue: 0.15)
        let teal = LightColor(red: 0.10, green: 0.40, blue: 0.44)
        let gold = LightColor(red: 0.95, green: 0.72, blue: 0.28)

        drawGift(
            in: context,
            rect: CGRect(x: cx - 97, y: groundY - 32, width: 45, height: 28),
            boxColor: red,
            ribbonColor: gold
        )
        drawGift(
            in: context,
            rect: CGRect(x: cx + 47, y: groundY - 28, width: 41, height: 24),
            boxColor: teal,
            ribbonColor: gold.mixed(with: .white, amount: 0.35)
        )
    }

    private func drawGift(
        in context: CGContext,
        rect: CGRect,
        boxColor: LightColor,
        ribbonColor: LightColor
    ) {
        context.setFillColor(cg(0, 0, 0, 0.16))
        context.fillEllipse(in: CGRect(x: rect.minX - 3, y: rect.maxY - 2, width: rect.width + 6, height: 6))

        let boxPath = CGPath(
            roundedRect: rect,
            cornerWidth: 2,
            cornerHeight: 2,
            transform: nil
        )

        context.saveGState()
        context.addPath(boxPath)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                boxColor.mixed(with: .white, amount: 0.18).cgColor(),
                boxColor.scaled(by: 0.65).cgColor()
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }

        context.setFillColor(ribbonColor.cgColor())
        context.fill(CGRect(x: rect.midX - 3.5, y: rect.minY, width: 7, height: rect.height))
        context.fill(CGRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6))
        context.restoreGState()

        context.addPath(boxPath)
        context.setStrokeColor(cg(0, 0, 0, 0.25))
        context.setLineWidth(0.6)
        context.strokePath()

        // Bow on top.
        let bowY = rect.minY - 5
        context.setFillColor(ribbonColor.mixed(with: .white, amount: 0.12).cgColor())
        context.fillEllipse(in: CGRect(x: rect.midX - 11, y: bowY - 4, width: 11, height: 8))
        context.fillEllipse(in: CGRect(x: rect.midX, y: bowY - 4, width: 11, height: 8))
        context.setFillColor(ribbonColor.scaled(by: 0.8).cgColor())
        context.fillEllipse(in: CGRect(x: rect.midX - 3, y: bowY - 3, width: 6, height: 6))
    }

    // MARK: - Tree light layers

    private func treeTiers(for size: CGSize) -> [Tier] {
        let groundY = size.height - 32
        return [
            Tier(baseY: groundY - 18, apexY: 158, halfWidth: 102),
            Tier(baseY: groundY - 72, apexY: 104, halfWidth: 84),
            Tier(baseY: groundY - 126, apexY: 62, halfWidth: 66)
        ]
    }

    private func ornamentLayout() -> [OrnamentLayout] {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return [] }

        let cx = size.width / 2
        let tiers = treeTiers(for: size)
        let specs: [(tier: Int, y: CGFloat, xFraction: CGFloat, radius: CGFloat)] = [
            (0, 282, -0.62, 4.5), (0, 266, 0.34, 3.6), (0, 250, -0.16, 5.0),
            (0, 234, 0.61, 3.7), (0, 218, -0.48, 4.3), (0, 202, 0.16, 4.6),
            (1, 228, -0.56, 3.8), (1, 212, 0.41, 4.6), (1, 196, -0.08, 3.6),
            (1, 180, 0.54, 4.2), (1, 164, -0.33, 4.5),
            (2, 176, -0.48, 4.2), (2, 160, 0.30, 3.6), (2, 144, -0.10, 4.6),
            (2, 128, 0.44, 3.7), (2, 112, -0.28, 4.2), (2, 96, 0.12, 3.6)
        ]

        var layout: [OrnamentLayout] = []
        layout.reserveCapacity(specs.count)
        for spec in specs {
            let tier = tiers[spec.tier]
            guard spec.y > tier.apexY, spec.y < tier.baseY else { continue }
            let halfAt = tier.halfWidth * (spec.y - tier.apexY) / (tier.baseY - tier.apexY)
            layout.append(
                OrnamentLayout(
                    center: CGPoint(x: cx + spec.xFraction * halfAt, y: spec.y),
                    radius: spec.radius
                )
            )
        }
        return layout
    }

    private func observeSettings() {
        settings.$theme
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshOrnaments() }
            .store(in: &cancellables)

        settings.$treeLightSource
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshOrnaments() }
            .store(in: &cancellables)

        settings.$treeLightGlow
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshOrnaments() }
            .store(in: &cancellables)

        settings.$treeLightStyle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshOrnaments() }
            .store(in: &cancellables)
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 1
        if bounds.size != builtSize || abs(scale - builtScale) > 0.01 {
            builtSize = bounds.size
            builtScale = scale
            needsDisplay = true
            refreshOrnaments()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshOrnaments()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshOrnaments()
    }

    private func refreshOrnaments() {
        ornamentLayers.forEach { $0.removeFromSuperlayer() }
        ornamentLayers.removeAll(keepingCapacity: true)

        guard
            settings.treeLightStyle != .off,
            bounds.width > 1,
            bounds.height > 1,
            let rootLayer = layer
        else { return }

        let palette = settings.treeLightSource.colors(matching: settings.theme)
        guard !palette.isEmpty else { return }

        let scale = window?.backingScaleFactor ?? 1
        let layout = ornamentLayout()

        for (index, ornament) in layout.enumerated() {
            let color = palette[index % palette.count]
            guard let sprite = makeOrnamentSprite(
                radius: ornament.radius,
                glow: settings.treeLightGlow,
                color: color,
                scale: scale
            ) else { continue }

            let diameter = ornamentSpriteDiameter(
                radius: ornament.radius,
                glow: settings.treeLightGlow
            )
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            // This layer-backed view uses a top-down coordinate space for its
            // sublayers, matching the Core Graphics drawing.
            layer.position = CGPoint(
                x: ornament.center.x,
                y: ornament.center.y
            )
            layer.contents = sprite
            layer.contentsGravity = .resize
            layer.contentsScale = scale
            layer.minificationFilter = .linear
            layer.magnificationFilter = .linear
            layer.isOpaque = false
            rootLayer.addSublayer(layer)
            ornamentLayers.append(layer)
        }

        applyOrnamentAnimations()
    }

    private func ornamentGlowRadius(radius: CGFloat, glow: Double) -> CGFloat {
        let clamped = CGFloat(min(max(glow, 0.1), 2.0))
        return max(radius * 3.8 * clamped, radius + 1)
    }

    private func ornamentSpriteDiameter(radius: CGFloat, glow: Double) -> CGFloat {
        ornamentGlowRadius(radius: radius, glow: glow) * 2
    }

    private func makeOrnamentSprite(
        radius: CGFloat,
        glow: Double,
        color: LightColor,
        scale: CGFloat
    ) -> CGImage? {
        let glowRadius = ornamentGlowRadius(radius: radius, glow: glow)
        let diameter = glowRadius * 2
        let pixelSize = max(8, Int((diameter * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        let center = CGPoint(x: diameter / 2, y: diameter / 2)

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                color.cgColor(alpha: 0.62),
                color.cgColor(alpha: 0.18),
                color.cgColor(alpha: 0)
            ] as CFArray,
            locations: [0, 0.42, 1]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: glowRadius,
                options: []
            )
        }

        let coreRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(color.mixed(with: .white, amount: 0.42).cgColor())
        context.fillEllipse(in: coreRect)

        context.setStrokeColor(color.scaled(by: 0.45).cgColor(alpha: 0.85))
        context.setLineWidth(0.7)
        context.strokeEllipse(in: coreRect)

        context.setFillColor(cg(1, 1, 1, 0.72))
        context.fillEllipse(
            in: CGRect(
                x: center.x - radius * 0.35,
                y: center.y + radius * 0.08,
                width: radius * 0.5,
                height: radius * 0.5
            )
        )

        return context.makeImage()
    }

    private func applyOrnamentAnimations() {
        for (index, layer) in ornamentLayers.enumerated() {
            layer.removeAnimation(forKey: "tree.lights")

            switch settings.treeLightStyle {
            case .off:
                layer.opacity = 0

            case .steady:
                layer.opacity = 1

            case .twinkle:
                let duration = 2.4 + Double(index % 6) * 0.45
                let phase = Double((index * 37) % 100) / 100.0
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [1.0, 0.78, 0.38, 0.78, 1.0].map { NSNumber(value: $0) }
                animation.duration = duration
                animation.timeOffset = phase * duration
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.isRemovedOnCompletion = false

                layer.opacity = 1
                layer.add(animation, forKey: "tree.lights")

            case .fade:
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [1.0, 0.55, 1.0].map { NSNumber(value: $0) }
                animation.duration = 4.5
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.isRemovedOnCompletion = false

                layer.opacity = 1
                layer.add(animation, forKey: "tree.lights")
            }
        }
    }

    private func drawStar(in context: CGContext, center: CGPoint) {
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                cg(1.0, 0.86, 0.42, 0.60),
                cg(1.0, 0.76, 0.22, 0.18),
                cg(1.0, 0.72, 0.18, 0)
            ] as CFArray,
            locations: [0, 0.45, 1]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: 52,
                options: []
            )
        }

        let path = starPath(center: center, outer: 21, inner: 9)
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [cg(1.0, 0.94, 0.63), cg(0.92, 0.62, 0.12)] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: center.x, y: center.y - 22),
                end: CGPoint(x: center.x, y: center.y + 22),
                options: []
            )
        }
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(cg(1.0, 0.86, 0.42, 0.95))
        context.setLineWidth(1.1)
        context.strokePath()

        context.setFillColor(cg(1, 1, 1, 0.55))
        context.fillEllipse(in: CGRect(x: center.x - 3, y: center.y - 4, width: 6, height: 6))
    }

    private func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = 5
        for index in 0..<(points * 2) {
            let angle = -Double.pi / 2 + Double(index) * .pi / Double(points)
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func drawSnowflakes(in context: CGContext, size: CGSize) {
        let flakes: [(CGFloat, CGFloat, CGFloat)] = [
            (34, 84, 1.1), (212, 96, 1.4), (56, 176, 1.0),
            (198, 238, 1.2), (28, 286, 1.0), (220, 306, 1.3)
        ]
        context.setFillColor(cg(1, 1, 1, 0.42))
        for (x, y, radius) in flakes {
            guard x < size.width, y < size.height else { continue }
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
    }

    // MARK: - Helpers

    private var colorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private func cg(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    // MARK: - Dragging / cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseEntered(with event: NSEvent) {
        if !isDragging {
            NSCursor.openHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        NSCursor.closedHand.set()
        window?.orderFrontRegardless()
        onDragBegan?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        onDragMoved?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
        NSCursor.openHand.set()
    }
}
