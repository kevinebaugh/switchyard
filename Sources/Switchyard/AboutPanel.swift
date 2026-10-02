import AppKit

/// The standard About window, with the licenses Switchyard ships with as its credits.
enum AboutPanel {
    @MainActor
    static func show() {
        let text = ["LICENSE", "THIRD_PARTY_NOTICES"]
            .compactMap { name in
                Bundle.main.url(forResource: name, withExtension: name == "LICENSE" ? nil : "md")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            }
            .joined(separator: "\n\n")
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
