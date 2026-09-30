import AppKit

/// The Switchyard mark as a menu-bar template image: one incoming link forking into
/// three routes, the chosen one solid. Geometry mirrors docs/logo.svg (1024-unit canvas).
enum MenuBarGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // The glyph spans roughly x 286…760 and y 213…810 in logo units; leave a margin.
            let scale = rect.height / 680
            context.translateBy(x: rect.midX - 518 * scale, y: rect.midY - 512 * scale)
            context.scaleBy(x: scale, y: scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            // Routes not taken, faded as one layer so overlaps don't darken.
            context.setAlpha(0.45)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(50)
            context.move(to: CGPoint(x: 512, y: 590))
            context.addCurve(to: CGPoint(x: 330, y: 392), control1: CGPoint(x: 512, y: 480), control2: CGPoint(x: 330, y: 490))
            context.move(to: CGPoint(x: 512, y: 590))
            context.addLine(to: CGPoint(x: 512, y: 326))
            context.strokePath()
            context.setLineWidth(34)
            context.strokeEllipse(in: CGRect(x: 330 - 44, y: 340 - 44, width: 88, height: 88))
            context.strokeEllipse(in: CGRect(x: 512 - 44, y: 274 - 44, width: 88, height: 88))
            context.endTransparencyLayer()
            context.setAlpha(1)

            // The chosen route.
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(62)
            context.move(to: CGPoint(x: 512, y: 760))
            context.addLine(to: CGPoint(x: 512, y: 590))
            context.addCurve(to: CGPoint(x: 694, y: 384), control1: CGPoint(x: 512, y: 480), control2: CGPoint(x: 694, y: 490))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 512 - 40, y: 770 - 40, width: 80, height: 80))
            context.fillEllipse(in: CGRect(x: 694 - 66, y: 340 - 66, width: 132, height: 132))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Switchyard"
        return image
    }()
}
