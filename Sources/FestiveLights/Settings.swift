import AppKit
import Combine

// MARK: - Colors

/// A plain sRGB color value. Using a small value type keeps palettes cheap to
/// copy and lets the renderer build cached CGColors / CGGradients from it.
struct LightColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = LightColor(red: 1, green: 1, blue: 1)

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    func scaled(by factor: Double) -> LightColor {
        LightColor(
            red: min(1, max(0, red * factor)),
            green: min(1, max(0, green * factor)),
            blue: min(1, max(0, blue * factor))
        )
    }

    func mixed(with other: LightColor, amount: Double) -> LightColor {
        let t = min(1, max(0, amount))
        return LightColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}

// MARK: - Animation modes

enum LightMode: String, CaseIterable, Identifiable {
    case steady
    case twinkle
    case chase
    case alternate
    case pulse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steady: return "Steady Glow"
        case .twinkle: return "Gentle Twinkle"
        case .chase: return "Chasing Wave"
        case .alternate: return "Alternating Flash"
        case .pulse: return "Fade Pulse"
        }
    }

    var symbolName: String {
        switch self {
        case .steady: return "sun.max.fill"
        case .twinkle: return "sparkles"
        case .chase: return "wind"
        case .alternate: return "bolt.fill"
        case .pulse: return "waveform.path.ecg"
        }
    }
}

// MARK: - Color themes

enum LightTheme: String, CaseIterable, Identifiable {
    case multicolor
    case warmWhite
    case icyBlue
    case candyCane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multicolor: return "Multicolor"
        case .warmWhite: return "Warm White"
        case .icyBlue: return "Icy Blue"
        case .candyCane: return "Candy Cane"
        }
    }

    var colors: [LightColor] {
        switch self {
        case .multicolor:
            return Self.multicolorPalette
        case .warmWhite:
            return Self.warmWhitePalette
        case .icyBlue:
            return Self.icyBluePalette
        case .candyCane:
            return Self.candyCanePalette
        }
    }

    private static let multicolorPalette: [LightColor] = [
        LightColor(red: 1.00, green: 0.16, blue: 0.12), // red
        LightColor(red: 0.18, green: 0.95, blue: 0.38), // green
        LightColor(red: 0.22, green: 0.52, blue: 1.00), // blue
        LightColor(red: 1.00, green: 0.84, blue: 0.20), // yellow
        LightColor(red: 1.00, green: 0.48, blue: 0.10)  // orange
    ]

    private static let warmWhitePalette: [LightColor] = [
        LightColor(red: 1.00, green: 0.84, blue: 0.58),
        LightColor(red: 1.00, green: 0.91, blue: 0.74),
        LightColor(red: 1.00, green: 0.76, blue: 0.46)
    ]

    private static let icyBluePalette: [LightColor] = [
        LightColor(red: 0.55, green: 0.86, blue: 1.00),
        LightColor(red: 0.80, green: 0.95, blue: 1.00),
        LightColor(red: 1.00, green: 1.00, blue: 1.00),
        LightColor(red: 0.36, green: 0.68, blue: 1.00)
    ]

    private static let candyCanePalette: [LightColor] = [
        LightColor(red: 1.00, green: 0.12, blue: 0.12),
        LightColor(red: 1.00, green: 0.96, blue: 0.94)
    ]
}

// MARK: - Window layering

enum OverlayLayering: String, CaseIterable, Identifiable {
    case desktop
    case alwaysOnTop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .alwaysOnTop: return "Always on Top"
        }
    }

    var detail: String {
        switch self {
        case .desktop: return "Behind app windows — visible on the desktop."
        case .alwaysOnTop: return "Above every app, including full-screen windows."
        }
    }
}

// MARK: - Tree lights

enum TreeLightSource: String, CaseIterable, Identifiable {
    case matchTheme
    case multicolor
    case warmWhite
    case icyBlue
    case candyCane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matchTheme: return "Match Theme"
        case .multicolor: return "Multicolor"
        case .warmWhite: return "Warm White"
        case .icyBlue: return "Icy Blue"
        case .candyCane: return "Candy Cane"
        }
    }

    func colors(matching theme: LightTheme) -> [LightColor] {
        switch self {
        case .matchTheme: return theme.colors
        case .multicolor: return LightTheme.multicolor.colors
        case .warmWhite: return LightTheme.warmWhite.colors
        case .icyBlue: return LightTheme.icyBlue.colors
        case .candyCane: return LightTheme.candyCane.colors
        }
    }
}

enum TreeLightStyle: String, CaseIterable, Identifiable {
    case off
    case steady
    case twinkle
    case fade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .steady: return "Steady"
        case .twinkle: return "Twinkle"
        case .fade: return "Fade"
        }
    }
}

// MARK: - Train

enum TrainCarType: String, CaseIterable, Identifiable {
    case passenger
    case freight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passenger: return "Passenger"
        case .freight: return "Freight"
        }
    }
}

// MARK: - Settings

/// Observable, persisted user preferences shared by the menu bar UI and the
/// overlay renderer.
final class Settings: ObservableObject {
    enum Keys {
        static let isOn = "festiveLights.isOn"
        static let mode = "festiveLights.mode"
        static let theme = "festiveLights.theme"
        static let glow = "festiveLights.glow"
        static let speed = "festiveLights.speed"
        static let layering = "festiveLights.layering"
        static let mouseSway = "festiveLights.mouseSway"
        static let showTree = "festiveLights.showTree"
        static let treeLightSource = "festiveLights.treeLightSource"
        static let treeLightGlow = "festiveLights.treeLightGlow"
        static let treeLightStyle = "festiveLights.treeLightStyle"
        static let showTrain = "festiveLights.showTrain"
        static let trainCarType = "festiveLights.trainCarType"
    }

    static let glowRange: ClosedRange<Double> = 0.25...1.75
    static let treeGlowRange: ClosedRange<Double> = 0.25...1.75
    static let speedRange: ClosedRange<Double> = 0.15...2.50

    @Published var isOn: Bool {
        didSet { defaults.set(isOn, forKey: Keys.isOn) }
    }

    @Published var mode: LightMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published var theme: LightTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var glow: Double {
        didSet { defaults.set(glow, forKey: Keys.glow) }
    }

    @Published var speed: Double {
        didSet { defaults.set(speed, forKey: Keys.speed) }
    }

    @Published var layering: OverlayLayering {
        didSet { defaults.set(layering.rawValue, forKey: Keys.layering) }
    }

    @Published var mouseSway: Bool {
        didSet { defaults.set(mouseSway, forKey: Keys.mouseSway) }
    }

    @Published var showTree: Bool {
        didSet { defaults.set(showTree, forKey: Keys.showTree) }
    }

    @Published var treeLightSource: TreeLightSource {
        didSet { defaults.set(treeLightSource.rawValue, forKey: Keys.treeLightSource) }
    }

    @Published var treeLightGlow: Double {
        didSet { defaults.set(treeLightGlow, forKey: Keys.treeLightGlow) }
    }

    @Published var treeLightStyle: TreeLightStyle {
        didSet { defaults.set(treeLightStyle.rawValue, forKey: Keys.treeLightStyle) }
    }

    @Published var showTrain: Bool {
        didSet { defaults.set(showTrain, forKey: Keys.showTrain) }
    }

    @Published var trainCarType: TrainCarType {
        didSet { defaults.set(trainCarType.rawValue, forKey: Keys.trainCarType) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedOn = defaults.object(forKey: Keys.isOn) as? Bool ?? true
        let storedMode = (defaults.string(forKey: Keys.mode)).flatMap(LightMode.init(rawValue:)) ?? .twinkle
        let storedTheme = (defaults.string(forKey: Keys.theme)).flatMap(LightTheme.init(rawValue:)) ?? .multicolor
        let storedGlow = (defaults.object(forKey: Keys.glow) as? Double) ?? 1.0
        let storedSpeed = (defaults.object(forKey: Keys.speed) as? Double) ?? 1.0
        let storedLayering = (defaults.string(forKey: Keys.layering)).flatMap(OverlayLayering.init(rawValue:)) ?? .desktop
        let storedMouseSway = defaults.object(forKey: Keys.mouseSway) as? Bool ?? true
        let storedShowTree = defaults.object(forKey: Keys.showTree) as? Bool ?? true
        let storedTreeSource = (defaults.string(forKey: Keys.treeLightSource)).flatMap(TreeLightSource.init(rawValue:)) ?? .matchTheme
        let storedTreeGlow = (defaults.object(forKey: Keys.treeLightGlow) as? Double) ?? 1.0
        let storedTreeStyle = (defaults.string(forKey: Keys.treeLightStyle)).flatMap(TreeLightStyle.init(rawValue:)) ?? .steady
        let storedShowTrain = defaults.object(forKey: Keys.showTrain) as? Bool ?? true
        let storedTrainCarType = (defaults.string(forKey: Keys.trainCarType)).flatMap(TrainCarType.init(rawValue:)) ?? .passenger

        self.isOn = storedOn
        self.mode = storedMode
        self.theme = storedTheme
        self.glow = min(max(storedGlow, Self.glowRange.lowerBound), Self.glowRange.upperBound)
        self.speed = min(max(storedSpeed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        self.layering = storedLayering
        self.mouseSway = storedMouseSway
        self.showTree = storedShowTree
        self.treeLightSource = storedTreeSource
        self.treeLightGlow = min(max(storedTreeGlow, Self.treeGlowRange.lowerBound), Self.treeGlowRange.upperBound)
        self.treeLightStyle = storedTreeStyle
        self.showTrain = storedShowTrain
        self.trainCarType = storedTrainCarType
    }

    /// Master state: true when any of the three decorations is currently on.
    var allDecorationsOn: Bool {
        isOn || showTree || showTrain
    }

    /// Turns the lights, tree and train off together, or back on together.
    func setAllDecorations(_ enabled: Bool) {
        isOn = enabled
        showTree = enabled
        showTrain = enabled
    }

    func resetAppearance() {
        mode = .twinkle
        theme = .multicolor
        glow = 1.0
        speed = 1.0
        layering = .desktop
        mouseSway = true
        showTree = true
        treeLightSource = .matchTheme
        treeLightGlow = 1.0
        treeLightStyle = .steady
        showTrain = true
        trainCarType = .passenger
    }
}
