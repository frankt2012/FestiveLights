import AppKit
import Combine
import CoreGraphics

/// A full-width, click-through overlay at the bottom of the screen. A steam
/// train runs behind tunnel portals at each edge, and loops back into the
/// opposite tunnel. The train is a single Core Animation layer so the movement
/// costs effectively no CPU.
final class TrainView: NSView {
    static let preferredHeight: CGFloat = 132
    static let trainHeight: CGFloat = 126
    static let portalWidth: CGFloat = 118

    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()
    private var trainLayer: CALayer?
    private var portalLayers: [CALayer] = []
    private var builtSize: CGSize = .zero
    private var builtScale: CGFloat = 0
    private let trainSpeed: CGFloat = 115

    init(settings: Settings) {
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        settings.$trainCarType
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildArtwork()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let height = bounds.height
        let width = bounds.width

        // Ballast strip.
        context.setFillColor(cg(0.16, 0.15, 0.14))
        context.fill(CGRect(x: 0, y: height - 13, width: width, height: 13))
        context.setFillColor(cg(0.22, 0.20, 0.18))
        for x in stride(from: CGFloat(0), to: width, by: 16) {
            context.fill(CGRect(x: x, y: height - 11, width: 6, height: 5))
        }

        // Rails and sleepers.
        context.setFillColor(cg(0.10, 0.09, 0.08))
        context.fill(CGRect(x: 0, y: height - 9, width: width, height: 4))
        context.setFillColor(cg(0.05, 0.05, 0.05))
        context.fill(CGRect(x: 0, y: height - 8, width: width, height: 2))
        context.setFillColor(cg(0.40, 0.41, 0.42))
        context.fill(CGRect(x: 0, y: height - 10, width: width, height: 1))

        context.restoreGState()
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 1
        if bounds.size != builtSize || abs(scale - builtScale) > 0.01 {
            builtSize = bounds.size
            builtScale = scale
            needsDisplay = true
            rebuildArtwork()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuildArtwork()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuildArtwork()
    }

    // MARK: - Artwork / animation

    private func rebuildArtwork() {
        guard
            bounds.width > 1,
            bounds.height > 1,
            let rootLayer = layer
        else { return }

        let scale = window?.backingScaleFactor ?? 1
        if bounds.size != builtSize || abs(scale - builtScale) > 0.01 {
            builtSize = bounds.size
            builtScale = scale
        }

        trainLayer?.removeFromSuperlayer()
        trainLayer = nil
        for layer in portalLayers {
            layer.removeFromSuperlayer()
        }
        portalLayers.removeAll(keepingCapacity: true)

        let train = TrainArtwork.makeTrain(carType: settings.trainCarType, scale: scale)
        if let image = train.image {
            let layer = makeLayer(
                image: image,
                pointSize: train.size,
                scale: scale,
                position: CGPoint(x: -train.size.width / 2, y: TrainView.trainHeight / 2)
            )
            rootLayer.addSublayer(layer)
            trainLayer = layer
            animate(layer, trainWidth: train.size.width)
        }

        for (mirrored, x) in [(false, TrainView.portalWidth / 2),
                              (true, bounds.width - TrainView.portalWidth / 2)] {
            let portal = TrainArtwork.makePortal(mirrored: mirrored, scale: scale)
            guard let image = portal.image else { continue }
            let layer = makeLayer(
                image: image,
                pointSize: portal.size,
                scale: scale,
                position: CGPoint(x: x, y: TrainView.trainHeight / 2)
            )
            rootLayer.addSublayer(layer)
            portalLayers.append(layer)
        }
    }

    private func makeLayer(
        image: CGImage,
        pointSize: CGSize,
        scale: CGFloat,
        position: CGPoint
    ) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: pointSize)
        layer.position = position
        layer.contents = image
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        layer.minificationFilter = .linear
        layer.magnificationFilter = .linear
        layer.isOpaque = false
        return layer
    }

    private func animate(_ layer: CALayer, trainWidth: CGFloat) {
        let start = -trainWidth / 2
        let end = bounds.width + trainWidth / 2
        let distance = end - start

        layer.position = CGPoint(x: start, y: TrainView.trainHeight / 2)

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = start
        animation.toValue = end
        animation.duration = CFTimeInterval(max(8, distance / trainSpeed))
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "train.run")
    }

    private func cg(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Train and portal artwork

private enum TrainArtwork {
    private static let height: CGFloat = 126
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    struct Artwork {
        let image: CGImage?
        let size: CGSize
    }

    static func makeTrain(carType: TrainCarType, scale: CGFloat) -> Artwork {
        let engineWidth: CGFloat = 160
        let carWidth: CGFloat = carType == .passenger ? 136 : 126
        let carCount = carType == .passenger ? 2 : 3
        let gap: CGFloat = 12
        let width = engineWidth + CGFloat(carCount) * carWidth + CGFloat(carCount) * gap
        let size = CGSize(width: width, height: height)

        let pixelWidth = max(1, Int((width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Artwork(image: nil, size: size)
        }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        let baseY: CGFloat = 118
        let engineX = width - engineWidth

        for index in 0..<carCount {
            let carX = engineX - gap - carWidth - CGFloat(index) * (carWidth + gap)
            if carType == .passenger {
                drawPassengerCar(context, x: carX, baseY: baseY, width: carWidth)
            } else {
                switch index {
                case 0:
                    drawTankCar(context, x: carX, baseY: baseY, width: carWidth)
                case 1:
                    drawBoxcar(context, x: carX, baseY: baseY, width: carWidth)
                default:
                    drawCaboose(context, x: carX, baseY: baseY, width: carWidth)
                }
            }
        }

        drawEngine(context, x: engineX, baseY: baseY)
        return Artwork(image: context.makeImage(), size: size)
    }

    static func makePortal(mirrored: Bool, scale: CGFloat) -> Artwork {
        let width: CGFloat = 118
        let size = CGSize(width: width, height: height)
        let pixelWidth = max(1, Int((width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Artwork(image: nil, size: size)
        }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        if mirrored {
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        drawPortal(context, width: width, height: height)
        return Artwork(image: context.makeImage(), size: size)
    }

    // MARK: - Engine

    private static func drawEngine(_ context: CGContext, x: CGFloat, baseY: CGFloat) {
        let black = cg(0.07, 0.075, 0.08)
        let graphite = cg(0.17, 0.18, 0.19)
        let graphiteLight = cg(0.34, 0.35, 0.37)
        let brass = cg(0.85, 0.67, 0.26)
        let red = cg(0.55, 0.10, 0.11)
        let warm = cg(1.0, 0.78, 0.40)
        let shadow = cg(0, 0, 0, 0.22)

        context.setFillColor(shadow)
        context.fillEllipse(in: CGRect(x: x + 8, y: baseY - 1, width: 152, height: 8))

        // Cowcatcher.
        let cow = CGMutablePath()
        cow.move(to: CGPoint(x: x + 160, y: baseY))
        cow.addLine(to: CGPoint(x: x + 143, y: baseY - 31))
        cow.addLine(to: CGPoint(x: x + 157, y: baseY - 31))
        cow.closeSubpath()
        context.addPath(cow)
        context.setFillColor(black)
        context.fillPath()
        context.setStrokeColor(brass.copy(alpha: 0.55) ?? brass)
        context.setLineWidth(1.0)
        for offset in stride(from: CGFloat(4), to: 15, by: 4) {
            context.move(to: CGPoint(x: x + 145 + offset, y: baseY - 27))
            context.addLine(to: CGPoint(x: x + 157, y: baseY - 2))
        }
        context.strokePath()

        // Drivers and leading truck.
        for cx in [x + 48, x + 84, x + 120] {
            drawWheel(context, center: CGPoint(x: cx, y: baseY - 14), radius: 14)
        }
        drawWheel(context, center: CGPoint(x: x + 148, y: baseY - 9), radius: 8.5)

        // Connecting rod.
        context.setStrokeColor(brass.copy(alpha: 0.75) ?? brass)
        context.setLineWidth(2.0)
        context.move(to: CGPoint(x: x + 34, y: baseY - 13))
        context.addLine(to: CGPoint(x: x + 136, y: baseY - 13))
        context.strokePath()

        // Frame.
        gradientRounded(
            context,
            CGRect(x: x + 14, y: baseY - 34, width: 144, height: 9),
            radius: 2,
            colors: [graphiteLight, black]
        )

        // Boiler.
        let boiler = CGRect(x: x + 52, y: baseY - 67, width: 92, height: 40)
        gradientRounded(context, boiler, radius: 18, colors: [graphiteLight, graphite, black])
        context.setFillColor(brass)
        for bandX in [x + 68, x + 96, x + 124] {
            context.fill(CGRect(x: bandX, y: baseY - 65, width: 2, height: 36))
        }

        // Smokebox and front.
        gradientRounded(
            context,
            CGRect(x: x + 136, y: baseY - 68, width: 18, height: 43),
            radius: 5,
            colors: [graphite, black]
        )
        context.setFillColor(cg(0.24, 0.25, 0.26))
        context.fillEllipse(in: CGRect(x: x + 143, y: baseY - 58, width: 15, height: 15))
        context.setFillColor(cg(0.055, 0.06, 0.065))
        context.fillEllipse(in: CGRect(x: x + 146, y: baseY - 55, width: 9, height: 9))

        // Smokestack.
        let stack = CGMutablePath()
        stack.move(to: CGPoint(x: x + 122, y: baseY - 64))
        stack.addLine(to: CGPoint(x: x + 125, y: baseY - 94))
        stack.addLine(to: CGPoint(x: x + 139, y: baseY - 94))
        stack.addLine(to: CGPoint(x: x + 142, y: baseY - 64))
        stack.closeSubpath()
        context.addPath(stack)
        context.setFillColor(black)
        context.fillPath()
        context.setFillColor(brass)
        context.fill(CGRect(x: x + 123, y: baseY - 97, width: 18, height: 4))
        context.setFillColor(cg(0.30, 0.31, 0.33))
        context.fill(CGRect(x: x + 124, y: baseY - 68, width: 16, height: 4))

        // Domes.
        gradientRounded(
            context,
            CGRect(x: x + 84, y: baseY - 76, width: 16, height: 13),
            radius: 6,
            colors: [brass, cg(0.56, 0.40, 0.12)]
        )
        gradientRounded(
            context,
            CGRect(x: x + 64, y: baseY - 73, width: 12, height: 10),
            radius: 5,
            colors: [graphiteLight, graphite]
        )

        // Cab.
        gradientRounded(
            context,
            CGRect(x: x + 8, y: baseY - 77, width: 54, height: 46),
            radius: 5,
            colors: [red.copy(alpha: 0.95) ?? red, cg(0.24, 0.035, 0.04)]
        )
        gradientRounded(
            context,
            CGRect(x: x + 3, y: baseY - 83, width: 64, height: 8),
            radius: 3,
            colors: [graphiteLight, black]
        )
        drawWindow(context, rect: CGRect(x: x + 16, y: baseY - 69, width: 15, height: 17), warm: warm)
        drawWindow(context, rect: CGRect(x: x + 37, y: baseY - 69, width: 15, height: 17), warm: warm)
        context.setFillColor(brass)
        context.fill(CGRect(x: x + 10, y: baseY - 48, width: 50, height: 2))

        // Headlamp with a warm glow.
        if let glow = CGGradient(
            colorsSpace: colorSpace,
            colors: [cg(1.0, 0.80, 0.32, 0.55), cg(1.0, 0.76, 0.22, 0)] as CFArray,
            locations: [0, 1]
        ) {
            context.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: x + 149, y: baseY - 52),
                startRadius: 0,
                endCenter: CGPoint(x: x + 149, y: baseY - 52),
                endRadius: 15,
                options: []
            )
        }
        context.setFillColor(warm)
        context.fillEllipse(in: CGRect(x: x + 144, y: baseY - 57, width: 10, height: 10))
        context.setFillColor(cg(1, 1, 1, 0.7))
        context.fillEllipse(in: CGRect(x: x + 147, y: baseY - 55, width: 4, height: 4))

        // Smoke, trailing left behind the stack.
        let puffs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (x + 112, baseY - 100, 9, 0.82),
            (x + 92, baseY - 108, 12, 0.62),
            (x + 67, baseY - 114, 14, 0.40),
            (x + 40, baseY - 118, 16, 0.24)
        ]
        for (px, py, radius, alpha) in puffs {
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [cg(0.88, 0.89, 0.92, alpha), cg(0.74, 0.76, 0.80, 0)] as CFArray,
                locations: [0, 1]
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: px, y: py),
                    startRadius: 0,
                    endCenter: CGPoint(x: px, y: py),
                    endRadius: radius,
                    options: []
                )
            }
        }
    }

    // MARK: - Passenger car

    private static func drawPassengerCar(
        _ context: CGContext,
        x: CGFloat,
        baseY: CGFloat,
        width: CGFloat
    ) {
        let green = cg(0.075, 0.29, 0.19)
        let greenLight = cg(0.16, 0.45, 0.30)
        let greenDark = cg(0.025, 0.13, 0.08)
        let cream = cg(0.88, 0.82, 0.68)
        let gold = cg(0.85, 0.67, 0.26)
        let warm = cg(1.0, 0.80, 0.43)

        context.setFillColor(cg(0, 0, 0, 0.20))
        context.fillEllipse(in: CGRect(x: x + 5, y: baseY - 1, width: width - 10, height: 8))

        gradientRounded(
            context,
            CGRect(x: x + 4, y: baseY - 31, width: width - 8, height: 8),
            radius: 2,
            colors: [cg(0.25, 0.26, 0.27), cg(0.08, 0.08, 0.09)]
        )

        gradientRounded(
            context,
            CGRect(x: x + 6, y: baseY - 66, width: width - 12, height: 40),
            radius: 5,
            colors: [greenLight, green, greenDark]
        )

        // Window band and individual windows.
        context.setFillColor(cg(0.04, 0.16, 0.10))
        context.fill(CGRect(x: x + 9, y: baseY - 60, width: width - 18, height: 19))
        for index in 0..<5 {
            drawWindow(
                context,
                rect: CGRect(x: x + 16 + CGFloat(index) * 22, y: baseY - 58, width: 15, height: 16),
                warm: warm
            )
        }

        // Gold trim.
        context.setFillColor(gold)
        context.fill(CGRect(x: x + 8, y: baseY - 35, width: width - 16, height: 2.5))

        // Roof.
        gradientRounded(
            context,
            CGRect(x: x + 2, y: baseY - 74, width: width - 4, height: 10),
            radius: 4,
            colors: [cream, cg(0.55, 0.52, 0.46)]
        )
        gradientRounded(
            context,
            CGRect(x: x + 24, y: baseY - 78, width: width - 48, height: 5),
            radius: 2,
            colors: [cream, cg(0.63, 0.60, 0.54)]
        )

        // Doors.
        context.setFillColor(cg(0.84, 0.78, 0.64))
        context.fill(CGRect(x: x + 9, y: baseY - 60, width: 2, height: 26))
        context.fill(CGRect(x: x + width - 11, y: baseY - 60, width: 2, height: 26))

        drawBogie(context, x: x + 35, baseY: baseY)
        drawBogie(context, x: x + width - 35, baseY: baseY)

        drawCouplings(context, x: x, width: width, baseY: baseY)
    }

    // MARK: - Freight cars

    private static func drawBoxcar(
        _ context: CGContext,
        x: CGFloat,
        baseY: CGFloat,
        width: CGFloat
    ) {
        let red = cg(0.44, 0.16, 0.11)
        let redLight = cg(0.63, 0.26, 0.18)
        let dark = cg(0.16, 0.10, 0.08)
        let cream = cg(0.85, 0.79, 0.65)
        let gold = cg(0.84, 0.66, 0.25)

        context.setFillColor(cg(0, 0, 0, 0.20))
        context.fillEllipse(in: CGRect(x: x + 5, y: baseY - 1, width: width - 10, height: 8))

        gradientRounded(
            context,
            CGRect(x: x + 4, y: baseY - 31, width: width - 8, height: 8),
            radius: 2,
            colors: [cg(0.26, 0.25, 0.23), cg(0.08, 0.08, 0.08)]
        )

        gradientRounded(
            context,
            CGRect(x: x + 6, y: baseY - 66, width: width - 12, height: 40),
            radius: 3,
            colors: [redLight, red, dark]
        )

        // Sliding door.
        context.setFillColor(cg(0.31, 0.12, 0.09))
        context.fill(CGRect(x: x + 38, y: baseY - 61, width: width - 76, height: 31))
        context.setStrokeColor(cg(0.67, 0.58, 0.45, 0.7))
        context.setLineWidth(1)
        for offset in stride(from: CGFloat(42), to: width - 40, by: 6) {
            context.move(to: CGPoint(x: x + offset, y: baseY - 59))
            context.addLine(to: CGPoint(x: x + offset, y: baseY - 32))
        }
        context.strokePath()
        context.setFillColor(gold)
        context.fill(CGRect(x: x + 38, y: baseY - 33, width: width - 76, height: 1.5))

        // Roof and lettering panel.
        gradientRounded(
            context,
            CGRect(x: x + 2, y: baseY - 72, width: width - 4, height: 8),
            radius: 2,
            colors: [cream, cg(0.44, 0.40, 0.34)]
        )
        context.setFillColor(cg(0.93, 0.90, 0.82, 0.72))
        context.fill(CGRect(x: x + 12, y: baseY - 52, width: 18, height: 3))
        context.fill(CGRect(x: x + width - 30, y: baseY - 52, width: 14, height: 3))

        drawBogie(context, x: x + 34, baseY: baseY)
        drawBogie(context, x: x + width - 34, baseY: baseY)
        drawCouplings(context, x: x, width: width, baseY: baseY)
    }

    private static func drawTankCar(
        _ context: CGContext,
        x: CGFloat,
        baseY: CGFloat,
        width: CGFloat
    ) {
        let teal = cg(0.16, 0.42, 0.42)
        let tealLight = cg(0.36, 0.64, 0.63)
        let dark = cg(0.06, 0.16, 0.16)
        let steel = cg(0.55, 0.59, 0.60)

        context.setFillColor(cg(0, 0, 0, 0.20))
        context.fillEllipse(in: CGRect(x: x + 5, y: baseY - 1, width: width - 10, height: 8))

        gradientRounded(
            context,
            CGRect(x: x + 4, y: baseY - 32, width: width - 8, height: 9),
            radius: 2,
            colors: [cg(0.28, 0.28, 0.28), cg(0.08, 0.08, 0.08)]
        )

        gradientRounded(
            context,
            CGRect(x: x + 10, y: baseY - 62, width: width - 20, height: 31),
            radius: 15,
            colors: [tealLight, teal, dark]
        )

        // Bands and valve.
        context.setFillColor(cg(0.10, 0.18, 0.19))
        context.fill(CGRect(x: x + 28, y: baseY - 60, width: 4, height: 27))
        context.fill(CGRect(x: x + width - 32, y: baseY - 60, width: 4, height: 27))
        gradientRounded(
            context,
            CGRect(x: x + width / 2 - 10, y: baseY - 68, width: 20, height: 8),
            radius: 3,
            colors: [steel, cg(0.35, 0.38, 0.38)]
        )
        context.setFillColor(steel)
        context.fill(CGRect(x: x + width / 2 - 2, y: baseY - 74, width: 4, height: 7))

        drawBogie(context, x: x + 36, baseY: baseY)
        drawBogie(context, x: x + width - 36, baseY: baseY)
        drawCouplings(context, x: x, width: width, baseY: baseY)
    }

    private static func drawCaboose(
        _ context: CGContext,
        x: CGFloat,
        baseY: CGFloat,
        width: CGFloat
    ) {
        let red = cg(0.49, 0.10, 0.09)
        let redLight = cg(0.68, 0.20, 0.15)
        let dark = cg(0.20, 0.045, 0.04)
        let cream = cg(0.88, 0.82, 0.68)
        let gold = cg(0.85, 0.68, 0.28)
        let warm = cg(1.0, 0.80, 0.43)

        context.setFillColor(cg(0, 0, 0, 0.20))
        context.fillEllipse(in: CGRect(x: x + 5, y: baseY - 1, width: width - 10, height: 8))

        gradientRounded(
            context,
            CGRect(x: x + 4, y: baseY - 31, width: width - 8, height: 8),
            radius: 2,
            colors: [cg(0.26, 0.25, 0.23), cg(0.08, 0.08, 0.08)]
        )

        gradientRounded(
            context,
            CGRect(x: x + 6, y: baseY - 63, width: width - 12, height: 37),
            radius: 4,
            colors: [redLight, red, dark]
        )

        // Cupola.
        gradientRounded(
            context,
            CGRect(x: x + width / 2 - 22, y: baseY - 82, width: 44, height: 22),
            radius: 3,
            colors: [redLight, red]
        )
        gradientRounded(
            context,
            CGRect(x: x + width / 2 - 25, y: baseY - 85, width: 50, height: 5),
            radius: 2,
            colors: [cream, cg(0.42, 0.37, 0.31)]
        )
        drawWindow(
            context,
            rect: CGRect(x: x + width / 2 - 13, y: baseY - 77, width: 12, height: 11),
            warm: warm
        )
        drawWindow(
            context,
            rect: CGRect(x: x + width / 2 + 1, y: baseY - 77, width: 12, height: 11),
            warm: warm
        )

        // Main body roof, windows and trim.
        gradientRounded(
            context,
            CGRect(x: x + 2, y: baseY - 70, width: width - 4, height: 8),
            radius: 3,
            colors: [cream, cg(0.44, 0.39, 0.32)]
        )
        drawWindow(
            context,
            rect: CGRect(x: x + 18, y: baseY - 57, width: 15, height: 15),
            warm: warm
        )
        drawWindow(
            context,
            rect: CGRect(x: x + width - 33, y: baseY - 57, width: 15, height: 15),
            warm: warm
        )
        context.setFillColor(gold)
        context.fill(CGRect(x: x + 8, y: baseY - 35, width: width - 16, height: 2))

        drawBogie(context, x: x + 34, baseY: baseY)
        drawBogie(context, x: x + width - 34, baseY: baseY)
        drawCouplings(context, x: x, width: width, baseY: baseY)
    }

    // MARK: - Shared pieces

    private static func drawBogie(_ context: CGContext, x: CGFloat, baseY: CGFloat) {
        context.setFillColor(cg(0.15, 0.15, 0.16))
        context.fill(CGRect(x: x - 18, y: baseY - 16, width: 36, height: 5))
        drawWheel(context, center: CGPoint(x: x - 11, y: baseY - 8), radius: 8)
        drawWheel(context, center: CGPoint(x: x + 11, y: baseY - 8), radius: 8)
    }

    private static func drawCouplings(_ context: CGContext, x: CGFloat, width: CGFloat, baseY: CGFloat) {
        context.setFillColor(cg(0.08, 0.08, 0.08))
        context.fill(CGRect(x: x - 2, y: baseY - 22, width: 6, height: 4))
        context.fill(CGRect(x: x + width - 4, y: baseY - 22, width: 6, height: 4))
    }

    private static func drawWheel(_ context: CGContext, center: CGPoint, radius: CGFloat) {
        let tire = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(cg(0.045, 0.05, 0.05))
        context.fillEllipse(in: tire)
        context.setFillColor(cg(0.32, 0.33, 0.34))
        context.fillEllipse(in: tire.insetBy(dx: 2, dy: 2))
        context.setFillColor(cg(0.10, 0.105, 0.11))
        context.fillEllipse(in: tire.insetBy(dx: 4.5, dy: 4.5))

        context.setStrokeColor(cg(0.58, 0.59, 0.6, 0.55))
        context.setLineWidth(1)
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            context.move(to: center)
            context.addLine(
                to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * (radius - 4),
                    y: center.y + CGFloat(sin(angle)) * (radius - 4)
                )
            )
        }
        context.strokePath()

        context.setFillColor(cg(0.82, 0.65, 0.25))
        context.fillEllipse(
            in: CGRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)
        )
    }

    private static func drawWindow(_ context: CGContext, rect: CGRect, warm: CGColor) {
        gradientRounded(
            context,
            rect,
            radius: 2,
            colors: [warm, cg(0.96, 0.57, 0.20)]
        )
        context.setFillColor(cg(1, 1, 1, 0.28))
        context.fill(CGRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: 2))
    }

    // MARK: - Portal

    private static func drawPortal(_ context: CGContext, width: CGFloat, height: CGFloat) {
        // Hill.
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: 0, y: height))
        hill.addLine(to: CGPoint(x: 0, y: height * 0.55))
        hill.addCurve(
            to: CGPoint(x: width * 0.45, y: height * 0.10),
            control1: CGPoint(x: width * 0.06, y: height * 0.34),
            control2: CGPoint(x: width * 0.20, y: height * 0.14)
        )
        hill.addCurve(
            to: CGPoint(x: width, y: height * 0.42),
            control1: CGPoint(x: width * 0.70, y: height * 0.04),
            control2: CGPoint(x: width * 0.94, y: height * 0.16)
        )
        hill.addLine(to: CGPoint(x: width, y: height))
        hill.closeSubpath()

        context.saveGState()
        context.addPath(hill)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                cg(0.20, 0.39, 0.21),
                cg(0.08, 0.23, 0.12),
                cg(0.035, 0.12, 0.075)
            ] as CFArray,
            locations: [0, 0.55, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: height),
                options: []
            )
        }

        // Stone face and blocks near the tunnel mouth.
        context.setFillColor(cg(0.38, 0.38, 0.36, 0.36))
        context.fill(CGRect(x: width * 0.46, y: height * 0.44, width: width * 0.54, height: height * 0.56))
        context.setStrokeColor(cg(0.25, 0.25, 0.23, 0.55))
        context.setLineWidth(1)
        for y in stride(from: height * 0.52, to: height, by: 13) {
            context.move(to: CGPoint(x: width * 0.5, y: y))
            context.addLine(to: CGPoint(x: width, y: y))
        }
        for x in stride(from: width * 0.55, to: width, by: 18) {
            context.move(to: CGPoint(x: x, y: height * 0.5))
            context.addLine(to: CGPoint(x: x, y: height))
        }
        context.strokePath()

        context.restoreGState()

        // Stone rim outline along the hill.
        context.addPath(hill)
        context.setStrokeColor(cg(0.06, 0.15, 0.09, 0.8))
        context.setLineWidth(1.5)
        context.strokePath()

        // Grass highlights.
        context.move(to: CGPoint(x: 0, y: height * 0.55))
        context.addCurve(
            to: CGPoint(x: width * 0.45, y: height * 0.10),
            control1: CGPoint(x: width * 0.06, y: height * 0.34),
            control2: CGPoint(x: width * 0.20, y: height * 0.14)
        )
        context.addCurve(
            to: CGPoint(x: width, y: height * 0.42),
            control1: CGPoint(x: width * 0.70, y: height * 0.04),
            control2: CGPoint(x: width * 0.94, y: height * 0.16)
        )
        context.setStrokeColor(cg(0.36, 0.57, 0.34, 0.55))
        context.setLineWidth(3)
        context.strokePath()

        // Tunnel mouth (opaque dark arch) on the inner side of the hill.
        let mouthX = width * 0.52
        let mouthWidth = width * 0.45
        let mouthTop = height * 0.47
        let mouthBottom = height
        let radius = mouthWidth / 2
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: mouthX, y: mouthBottom))
        mouth.addLine(to: CGPoint(x: mouthX, y: mouthTop + radius))
        mouth.addQuadCurve(
            to: CGPoint(x: mouthX + mouthWidth, y: mouthTop + radius),
            control: CGPoint(x: mouthX + radius, y: mouthTop)
        )
        mouth.addLine(to: CGPoint(x: mouthX + mouthWidth, y: mouthBottom))
        mouth.closeSubpath()

        context.addPath(mouth)
        context.setFillColor(cg(0.015, 0.025, 0.02))
        context.fillPath()

        context.addPath(mouth)
        context.setStrokeColor(cg(0.47, 0.46, 0.42))
        context.setLineWidth(5)
        context.strokePath()
        context.addPath(mouth)
        context.setStrokeColor(cg(0.22, 0.21, 0.19))
        context.setLineWidth(2)
        context.strokePath()

        // Keystone and a couple of stone blocks.
        context.setFillColor(cg(0.52, 0.50, 0.45))
        context.fill(
            CGRect(
                x: mouthX + mouthWidth / 2 - 5,
                y: mouthTop - 2,
                width: 10,
                height: 11
            )
        )
        context.fill(CGRect(x: mouthX - 8, y: height * 0.72, width: 10, height: 6))
        context.fill(CGRect(x: mouthX + mouthWidth + 1, y: height * 0.70, width: 8, height: 7))

        // Tufts of grass on the crown.
        context.setStrokeColor(cg(0.40, 0.61, 0.33, 0.55))
        context.setLineWidth(1.2)
        for offset in stride(from: CGFloat(10), to: width * 0.45, by: 13) {
            let x = offset
            context.move(to: CGPoint(x: x, y: height * 0.20))
            context.addLine(to: CGPoint(x: x + 2, y: height * 0.16))
            context.move(to: CGPoint(x: x, y: height * 0.20))
            context.addLine(to: CGPoint(x: x - 2, y: height * 0.16))
        }
        context.strokePath()
    }

    // MARK: - Helpers

    private static func cg(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func fillRounded(
        _ context: CGContext,
        _ rect: CGRect,
        radius: CGFloat,
        color: CGColor
    ) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(color)
        context.fillPath()
    }

    private static func gradientRounded(
        _ context: CGContext,
        _ rect: CGRect,
        radius: CGFloat,
        colors: [CGColor]
    ) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: nil
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.minX, y: rect.maxY),
                options: []
            )
        }
        context.restoreGState()
    }
}
