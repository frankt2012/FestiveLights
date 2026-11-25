import Foundation
import QuartzCore

/// Builds a seamless CAKeyframeAnimation waveform for one bulb.
///
/// Modes are expressed as periodic functions of a normalised loop position, so
/// Core Animation can repeat them forever without any per-frame work in the app.
enum LightAnimator {
    struct Specification {
        let values: [NSNumber]
        let duration: CFTimeInterval
    }

    private static let sampleCount = 72

    static func specification(
        mode: LightMode,
        index: Int,
        count: Int,
        phase: Double,
        rate: Double,
        speed: Double
    ) -> Specification {
        let period: Double
        let evaluate: (Double) -> Double

        switch mode {
        case .steady:
            period = 6.0
            evaluate = { u in
                0.93 + 0.07 * sin(2 * .pi * u + phase)
            }

        case .twinkle:
            period = 7.0
            evaluate = { u in
                let slow = sin(2 * .pi * (2 * u) + phase)
                let fast = sin(2 * .pi * (5 * u) + phase * 1.9 + rate * 0.8)
                let mixed = max(0, slow * 0.65 + fast * 0.35)
                return 0.13 + 0.87 * pow(mixed, 1.6)
            }

        case .chase:
            period = 4.5
            let position = count > 1 ? Double(index) / Double(count - 1) : 0
            evaluate = { u in
                var offset = (position - u).truncatingRemainder(dividingBy: 1)
                if offset < 0 { offset += 1 }
                let distance = min(offset, 1 - offset)
                let pulse = max(0, 1 - distance / 0.14)
                return 0.10 + 0.90 * pow(pulse, 1.35)
            }

        case .alternate:
            period = 3.2
            let sign = index.isMultiple(of: 2) ? 1.0 : -1.0
            evaluate = { u in
                let shaped = 0.5 + 0.5 * tanh(sin(2 * .pi * u) * 2.6 * sign)
                return 0.10 + 0.90 * shaped
            }

        case .pulse:
            period = 4.5
            evaluate = { u in
                let base = 0.5 + 0.5 * sin(2 * .pi * u + phase * 0.15)
                return 0.20 + 0.80 * pow(base, 1.4)
            }
        }

        var values: [NSNumber] = []
        values.reserveCapacity(sampleCount + 1)
        for sample in 0...sampleCount {
            let u = Double(sample) / Double(sampleCount)
            let value = min(1, max(0, evaluate(u)))
            values.append(NSNumber(value: value))
        }

        return Specification(
            values: values,
            duration: period / max(speed, 0.05)
        )
    }
}
