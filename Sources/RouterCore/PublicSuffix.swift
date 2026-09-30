import Foundation

/// A deliberately small public-suffix list: enough to turn `docs.google.com` into
/// `google.com` and `foo.github.io` into `foo.github.io` without bundling the full PSL.
public enum PublicSuffix {
    static let multiLabelSuffixes: Set<String> = [
        // ICANN second-level suffixes that are common in practice.
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "org.nz", "co.jp", "ne.jp", "or.jp", "ac.jp",
        "co.in", "co.za", "co.kr", "com.br", "com.mx", "com.ar", "com.cn",
        "com.hk", "com.sg", "com.tw", "com.tr", "com.ua", "co.il",
        // Private suffixes where every subdomain belongs to someone different.
        "github.io", "githubusercontent.com", "gitlab.io", "herokuapp.com",
        "vercel.app", "netlify.app", "pages.dev", "workers.dev", "web.app",
        "firebaseapp.com", "appspot.com", "cloudfront.net", "azurewebsites.net",
        "ngrok.io", "ngrok-free.app", "ngrok.app", "blogspot.com", "fly.dev",
        "onrender.com", "glitch.me", "replit.app", "repl.co", "s3.amazonaws.com",
        "myshopify.com", "wordpress.com", "substack.com", "notion.site",
    ]

    /// The shortest domain someone can own for `host`: `docs.google.com` → `google.com`,
    /// `news.bbc.co.uk` → `bbc.co.uk`, `kev.github.io` → `kev.github.io`.
    public static func registrableDomain(for host: String) -> String {
        let host = RuleKey.normalizeHost(host)
        if isIPAddress(host) { return host }

        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }

        // Longest known multi-label suffix wins.
        for start in 1..<(labels.count - 1) {
            let suffix = labels[start...].joined(separator: ".")
            if multiLabelSuffixes.contains(suffix) {
                return labels[(start - 1)...].joined(separator: ".")
            }
        }
        return labels.suffix(2).joined(separator: ".")
    }

    static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
