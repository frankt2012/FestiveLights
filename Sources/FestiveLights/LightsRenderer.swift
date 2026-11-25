import AppKit
import QuartzCore

struct BulbLayout {
    let x: CGFloat
    let wireY: CGFloat
    let colorIndex: Int
    let phase: Double
    let rate: Double
}

/// Generates the static artwork for one overlay window:
///
/// * a full-width base image with the draped wire, clips, sockets and dark
///   unlit glass, and
/// * one pre-rendered image per bulb color holding a fully lit C9 bulb plus its
///   radial bloom.
///
/// The overlay view then animates the opacity of one Core Animation layer per
/// bulb, so the animation itself is composited by the GPU and costs almost no
/// CPU.
final class LightsRenderer {
    enum BulbArtwork: Equatable {
        case unlit
        case lit
    }

    static let bulbCenterOffsetY: CGFloat = 15.5
    static let bulbSocketTopOffsetFromWireY: CGFloat = 0.8
    /// Glass top, i.e. the pivot the bulb swings around, measured down from the wire.
    static let bulbPivotOffsetFromWireY: CGFloat = 5.5
    /// Distance from the glass top to the bulb body centre.
    static let bulbHalfHeight: CGFloat = 10

    private let topY: CGFloat = 3
    private let sagDepth: CGFloat = 16
    private let bulbWidth: CGFloat = 12.5
    private let bulbHeight: CGFloat = 20
    private let socketHeight: CGFloat = 6
    private let socketOverlap: CGFloat = 1.3
    private let spritePadding: CGFloat = 0.8

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private(set) var bulbs: [BulbLayout] = []
    private var supports: [CGFloat] = []
    private var wirePath: CGPath?

    private var preparedTheme: LightTheme?
    private var preparedWidth: CGFloat = -1
    private var palette: [LightColor] = []

    private struct GradientKey: Hashable {
        let colorIndex: Int
        let bucket: Int
    }

    private var gradients: [GradientKey: CGGradient] = [:]

    // MARK: - Public

    func bulbSpriteDiameter(glow: Double) -> CGFloat {
        44 + 12 * CGFloat(min(max(glow, 0.1), 2.0))
    }

    func prepare(width: CGFloat, theme: LightTheme) {
        if theme != preparedTheme {
            preparedTheme = theme
            palette = theme.colors
            gradients.removeAll(keepingCapacity: true)
            preparedWidth = -1 // Palette size drives the bulb colour cycle.
        }
        if abs(width - preparedWidth) > 0.5 || supports.isEmpty {
            preparedWidth = width
            rebuildLayout(width: width)
        }
    }

    /// The complete static strip: wire, clips and fixed bulb sockets.
    func makeBaseImage(size: CGSize, scale: CGFloat, theme: LightTheme) -> CGImage? {
        prepare(width: size.width, theme: theme)
        guard size.width > 1, size.height > 1 else { return nil }

        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
        guard let context = makeContext(width: pixelWidth, height: pixelHeight) else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        if let wirePath {
            drawWire(in: context, path: wirePath)
        }

        // Sockets stay welded to the wire. Glass is a separate per-bulb layer
        // so it can swing underneath without dragging the socket with it.
        for bulb in bulbs {
            drawSocket(
                in: context,
                centerX: bulb.x,
                socketTop: bulb.wireY + Self.bulbSocketTopOffsetFromWireY
            )
        }

        return context.makeImage()
    }

    /// The glass and optional glow of one bulb, centred on the bulb body. The
    /// socket deliberately is not included: it stays fixed on the wire while
    /// this image rotates beneath it. The overlay animates this layer's opacity.
    func makeBulbImage(
        colorIndex: Int,
        glow: Double,
        scale: CGFloat,
        theme: LightTheme,
        artwork: BulbArtwork
    ) -> CGImage? {
        if theme != preparedTheme {
            preparedTheme = theme
            palette = theme.colors
            gradients.removeAll(keepingCapacity: true)
        }
        guard palette.indices.contains(colorIndex) else { return nil }

        let diameter = bulbSpriteDiameter(glow: glow)
        let pixelSize = max(8, Int((diameter * scale).rounded(.up)))
        guard let context = makeContext(width: pixelSize, height: pixelSize) else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: diameter)
        context.scaleBy(x: 1, y: -1)

        let center = diameter / 2

        if artwork == .lit {
            // Soft bloom, baked into the bulb sprite and rotated with it.
            let color = palette[colorIndex]
            let colors = [
                color.cgColor(alpha: 0.95),
                color.cgColor(alpha: 0.50),
                color.cgColor(alpha: 0.14),
                color.cgColor(alpha: 0.0)
            ]
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors as CFArray,
                locations: [0, 0.24, 0.60, 1]
            ) {
                context.saveGState()
                context.setBlendMode(.plusLighter)
                context.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: center, y: center),
                    startRadius: 0,
                    endCenter: CGPoint(x: center, y: center),
                    endRadius: diameter / 2,
                    options: []
                )
                context.restoreGState()
            }
        }

        drawGlass(
            in: context,
            centerX: center,
            topY: center - Self.bulbHalfHeight,
            amount: artwork == .lit ? 1.0 : 0.06,
            colorIndex: colorIndex
        )

        return context.makeImage()
    }

    // MARK: - Layout

    private func rebuildLayout(width: CGFloat) {
        let period = max(170, min(280, width / 6.5))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: topY))

        var start: CGFloat = 0
        while start < width {
            let end = min(start + period, width)
            path.addQuadCurve(
                to: CGPoint(x: end, y: topY),
                control: CGPoint(x: (start + end) / 2, y: topY + sagDepth * 2)
            )
            start = end
        }
        wirePath = path

        supports = stride(from: CGFloat(0), through: width, by: period).map { $0 }
        if let last = supports.last, width - last > 4 {
            supports.append(width)
        }

        let bulbCount = max(1, Int((width / 54).rounded()))
        let spacing = width / CGFloat(bulbCount)
        var newBulbs: [BulbLayout] = []
        newBulbs.reserveCapacity(bulbCount)

        for index in 0..<bulbCount {
            let x = spacing * (CGFloat(index) + 0.5)
            let y = wireY(at: x, width: width, period: period)
            let random = pseudoRandom(index)
            newBulbs.append(
                BulbLayout(
                    x: x,
                    wireY: y,
                    colorIndex: index % max(palette.count, 1),
                    phase: random * .pi * 2,
                    rate: 0.6 + random * 1.4
                )
            )
        }
        bulbs = newBulbs
    }

    private func wireY(at x: CGFloat, width: CGFloat, period: CGFloat) -> CGFloat {
        let clamped = min(max(x, 0), width)
        let segmentStart = (clamped / period).rounded(.down) * period
        let segmentEnd = min(segmentStart + period, width)
        let length = max(segmentEnd - segmentStart, 0.001)
        let u = (clamped - segmentStart) / length
        return topY + sagDepth * 4 * u * (1 - u)
    }

    private func pseudoRandom(_ index: Int) -> Double {
        let raw = sin(Double(index) * 12.9898 + 0.37) * 43758.5453
        return raw - raw.rounded(.down)
    }

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    // MARK: - Wire

    private func drawWire(in context: CGContext, path: CGPath) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.addPath(path)
        context.setStrokeColor(CGColor(srgbRed: 0.055, green: 0.105, blue: 0.070, alpha: 0.98))
        context.setLineWidth(2.6)
        context.strokePath()

        context.saveGState()
        context.translateBy(x: 0, y: -0.7)
        context.addPath(path)
        context.setStrokeColor(CGColor(srgbRed: 0.34, green: 0.48, blue: 0.36, alpha: 0.35))
        context.setLineWidth(0.7)
        context.strokePath()
        context.restoreGState()

        let clipColor = CGColor(srgbRed: 0.13, green: 0.15, blue: 0.13, alpha: 1)
        let clipHighlight = CGColor(srgbRed: 0.42, green: 0.45, blue: 0.42, alpha: 0.45)
        for x in supports {
            let clipRect = CGRect(x: x - 2.1, y: 0, width: 4.2, height: 6.5)
            context.addPath(CGPath(roundedRect: clipRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            context.setFillColor(clipColor)
            context.fillPath()
            context.setFillColor(clipHighlight)
            context.fill(CGRect(x: x - 1.2, y: 0.9, width: 2.4, height: 1.1))
        }

        context.restoreGState()
    }

    // MARK: - Bulb artwork

    private func drawSocket(
        in context: CGContext,
        centerX x: CGFloat,
        socketTop: CGFloat
    ) {
        let socketFill = CGColor(srgbRed: 0.15, green: 0.16, blue: 0.15, alpha: 1)
        let socketHighlight = CGColor(srgbRed: 0.46, green: 0.48, blue: 0.45, alpha: 0.55)
        let socketShadow = CGColor(srgbRed: 0.04, green: 0.05, blue: 0.04, alpha: 0.8)

        let socketRect = CGRect(x: x - 4.2, y: socketTop, width: 8.4, height: socketHeight)
        context.addPath(CGPath(roundedRect: socketRect, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
        context.setFillColor(socketFill)
        context.fillPath()

        context.setFillColor(socketHighlight)
        context.fill(CGRect(x: x - 3.2, y: socketRect.minY + 0.8, width: 6.4, height: 0.8))

        context.setFillColor(socketShadow)
        context.fill(CGRect(x: x - 3.6, y: socketRect.maxY - 1.1, width: 7.2, height: 1.0))
    }

    private func drawGlass(
        in context: CGContext,
        centerX x: CGFloat,
        topY: CGFloat,
        amount: Double,
        colorIndex: Int
    ) {
        let bulbRect = CGRect(
            x: x - bulbWidth / 2,
            y: topY,
            width: bulbWidth,
            height: bulbHeight
        )
        let glassPath = Self.bulbPath(in: bulbRect)

        context.saveGState()
        context.addPath(glassPath)
        context.clip()

        if let gradient = makeGradient(colorIndex: colorIndex, brightness: amount) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bulbRect.midX, y: bulbRect.minY - 1),
                end: CGPoint(x: bulbRect.midX, y: bulbRect.maxY + 1),
                options: []
            )
        }

        context.setBlendMode(.plusLighter)
        let coreAlpha = 0.14 + 0.62 * amount
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: coreAlpha))
        context.fillEllipse(
            in: CGRect(
                x: x - bulbWidth * 0.24,
                y: bulbRect.minY + bulbHeight * 0.20,
                width: bulbWidth * 0.48,
                height: bulbHeight * 0.34
            )
        )
        if amount > 0.35 {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30 * amount))
            context.fillEllipse(
                in: CGRect(
                    x: x - bulbWidth * 0.11,
                    y: bulbRect.minY + bulbHeight * 0.28,
                    width: bulbWidth * 0.22,
                    height: bulbHeight * 0.16
                )
            )
        }
        context.restoreGState()

        context.addPath(glassPath)
        let rim = palette.isEmpty ? LightColor.white : palette[colorIndex % palette.count]
        context.setStrokeColor(rim.scaled(by: 0.45 + 0.3 * amount).cgColor(alpha: 0.55))
        context.setLineWidth(0.6)
        context.strokePath()
    }

    private static func bulbPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = rect.midX
        let top = rect.minY
        let bottom = rect.maxY
        let halfW = rect.width / 2
        let neck = rect.width * 0.20
        let height = rect.height
        let widestY = top + height * 0.55

        path.move(to: CGPoint(x: cx - neck, y: top))
        path.addQuadCurve(
            to: CGPoint(x: cx + neck, y: top),
            control: CGPoint(x: cx, y: top - 1.4)
        )
        path.addCurve(
            to: CGPoint(x: cx + halfW, y: widestY),
            control1: CGPoint(x: cx + neck + rect.width * 0.10, y: top + height * 0.16),
            control2: CGPoint(x: cx + halfW * 0.96, y: top + height * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: bottom),
            control1: CGPoint(x: cx + halfW, y: top + height * 0.78),
            control2: CGPoint(x: cx + rect.width * 0.22, y: bottom)
        )
        path.addCurve(
            to: CGPoint(x: cx - halfW, y: widestY),
            control1: CGPoint(x: cx - rect.width * 0.22, y: bottom),
            control2: CGPoint(x: cx - halfW, y: top + height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: cx - neck, y: top),
            control1: CGPoint(x: cx - halfW * 0.96, y: top + height * 0.38),
            control2: CGPoint(x: cx - neck - rect.width * 0.10, y: top + height * 0.16)
        )
        path.closeSubpath()
        return path
    }

    private func makeGradient(colorIndex: Int, brightness: Double) -> CGGradient? {
        guard palette.indices.contains(colorIndex) else { return nil }

        let bucket = max(0, min(23, Int(brightness * 23)))
        let key = GradientKey(colorIndex: colorIndex, bucket: bucket)
        if let cached = gradients[key] { return cached }

        let level = Double(bucket) / 23.0
        let base = palette[colorIndex].scaled(by: 0.26 + 0.74 * level)
        let top = base.mixed(with: .white, amount: 0.52)
        let bottom = base.scaled(by: 0.52)

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [top.cgColor(), base.cgColor(), bottom.cgColor()] as CFArray,
            locations: [0, 0.45, 1]
        ) else { return nil }

        gradients[key] = gradient
        return gradient
    }
}
