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
            .map(plainText)
            .joined(separator: "\n\n")
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// The license files are Markdown with hard-wrapped lines. Show them as plain, reflowed
    /// paragraphs: no code fences, link syntax or emphasis markers, and tables as one line per row.
    static func plainText(_ markdown: String) -> String {
        var paragraphs: [String] = []
        var current: [String] = []

        func flush() {
            if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
            current = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("|") {
                flush()
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                // Skip the header separator row (| --- | --- |).
                guard !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) else { continue }
                paragraphs.append(cells.map(inline).joined(separator: " · "))
                continue
            }
            if line.hasPrefix("#") {
                flush()
                paragraphs.append(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)).uppercased())
                continue
            }
            current.append(inline(line))
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    /// `[text](url)` → `text (url)`, and drop `code` and **emphasis** markers.
    private static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1 ($2)", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
    }
}
