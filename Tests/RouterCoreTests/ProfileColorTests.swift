import Foundation
import Testing
@testable import RouterCore

@Suite struct ProfileColorTests {
    /// WCAG contrast ratio between two luminances.
    func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    let pastels: [UInt32] = [0xFFE0F7FA, 0xFFFCE4EC, 0xFFFFF9C4, 0xFFE8F5E9]   // pale cyan, pink, yellow, green
    let darks: [UInt32] = [0xFF1A237E, 0xFF3E2723, 0xFF000000]

    @Test func pastelsBecomeReadableOnLightChips() {
        // Chips are a light tint over a near-white window (luminance ~0.85).
        for argb in pastels + darks {
            let text = ProfileColor.readableText(argb: argb, dark: false)
            #expect(contrast(text.luminance, 0.85) >= 4.0, "0x\(String(argb, radix: 16))")
        }
    }

    @Test func darkColorsBecomeReadableOnDarkChips() {
        // Dark mode: chip over a near-black window (luminance ~0.03).
        for argb in pastels + darks {
            let text = ProfileColor.readableText(argb: argb, dark: true)
            #expect(contrast(text.luminance, 0.03) >= 4.5, "0x\(String(argb, radix: 16))")
        }
    }

    @Test func alreadyReadableColorsAreUntouched() {
        let blue: UInt32 = 0xFF1565C0   // mid blue: fine on light
        #expect(ProfileColor.readableText(argb: blue, dark: false) == ProfileColor.RGB(argb: blue))
        #expect(ProfileColor.readableText(argb: 0xFFFFE082, dark: true) == ProfileColor.RGB(argb: 0xFFFFE082))
    }

    @Test func hueIsKept() {
        // Darkening mixes toward black, which keeps the channel ratios.
        let text = ProfileColor.readableText(argb: 0xFFFCE4EC, dark: false)
        #expect(text.red > text.green && text.red > text.blue)
    }
}
