import Foundation

/// Profile colors come straight from the browser, and Chrome's theme colors can be pale
/// pastels. For text, keep the hue but move the brightness until it reads on the chip:
/// darker in light mode, lighter in dark mode.
public enum ProfileColor {
    public struct RGB: Equatable, Sendable {
        public var red, green, blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(argb: UInt32) {
            red = Double((argb >> 16) & 0xFF) / 255
            green = Double((argb >> 8) & 0xFF) / 255
            blue = Double(argb & 0xFF) / 255
        }

        /// Relative luminance (WCAG), 0 = black, 1 = white.
        public var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// Luminance limits that keep chip text readable on a light or dark background.
    static let maxLuminanceOnLight = 0.15
    static let minLuminanceOnDark = 0.45

    public static func readableText(argb: UInt32, dark: Bool) -> RGB {
        let color = RGB(argb: argb)
        if dark {
            guard color.luminance < minLuminanceOnDark else { return color }
            // Mix toward white until it's light enough.
            return search { t in mix(color, with: RGB(red: 1, green: 1, blue: 1), t) } until: { $0.luminance >= minLuminanceOnDark }
        } else {
            guard color.luminance > maxLuminanceOnLight else { return color }
            // Mix toward black until it's dark enough.
            return search { t in mix(color, with: RGB(red: 0, green: 0, blue: 0), t) } until: { $0.luminance <= maxLuminanceOnLight }
        }
    }

    private static func mix(_ a: RGB, with b: RGB, _ t: Double) -> RGB {
        RGB(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t)
    }

    /// The smallest mix (in 2% steps) that satisfies the condition.
    private static func search(_ make: (Double) -> RGB, until done: (RGB) -> Bool) -> RGB {
        for step in 1...50 {
            let candidate = make(Double(step) / 50)
            if done(candidate) { return candidate }
        }
        return make(1)
    }
}
