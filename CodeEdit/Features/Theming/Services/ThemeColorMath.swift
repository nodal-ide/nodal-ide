import SwiftUI
import CodeEditLang

struct ThemeRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red.clampedToUnit
        self.green = green.clampedToUnit
        self.blue = blue.clampedToUnit
    }

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard [3, 6, 8].contains(value.count), value.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        let digits: String
        switch value.count {
        case 3:
            digits = value.map { "\($0)\($0)" }.joined()
        case 8:
            digits = String(value.prefix(6))
        default:
            digits = value
        }
        guard let number = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var hexString: String {
        let components = [red, green, blue].map {
            Int(($0 * 255).rounded()).clamped(to: 0...255)
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var isLight: Bool {
        relativeLuminance > 0.5
    }

    func mixed(with other: ThemeRGB, amount: Double) -> ThemeRGB {
        let amount = amount.clampedToUnit
        return ThemeRGB(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    func contrastRatio(with other: ThemeRGB) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func ensuringContrast(
        against background: ThemeRGB,
        minimum: Double = 4.5,
        target: ThemeRGB
    ) -> ThemeRGB {
        guard contrastRatio(with: background) < minimum else { return self }
        var result = self
        for step in 0..<8 {
            result = mixed(with: target, amount: Double(step + 1) / 8)
            if result.contrastRatio(with: background) >= minimum {
                return result
            }
        }
        return result
    }
}

private extension Double {
    var clampedToUnit: Double {
        clamped(to: 0...1)
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
