// Links — pālana's outward URLs, in one place (ho-12). The Help menu, the
// About panel, and the update announce all read from here, so the site moves in
// one edit. The binary is sold on Payhip; the website is the hub that carries
// the buy button and the changelog, so "get the update" and "download" point at
// the site, not at a GitHub release.

import Foundation

/// The canonical external links.
enum Links {
    /// The product site — the download/changelog hub (Payhip buy button lives here).
    static let website = url("https://palana.sageframe.net")

    /// The help site.
    static let help = url("https://palana.sageframe.net/help")

    /// The public source repository (GPL-3.0).
    static let github = url("https://github.com/sageframe-no-kaji/palana")

    /// Filing a bug — a pre-filled issue on the public tracker.
    ///
    /// The running version and macOS are baked into the body, so every report
    /// carries the facts you'd otherwise have to ask for, and the reporter skips
    /// the "what version am I on" friction. A `.github` issue template structures
    /// a raw `issues/new` for anyone who arrives without the query.
    static var reportBug: URL {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "dev build"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
            **What happened**


            **What I expected**


            **Steps to reproduce**


            ---
            pālana \(version) · macOS \(os)
            """
        var components = URLComponents(
            url: url("https://github.com/sageframe-no-kaji/palana/issues/new"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: "[bug] "),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        return components?.url ?? url("https://github.com/sageframe-no-kaji/palana/issues/new")
    }

    /// Support the work — the "Buy Me a Coffee" page.
    static let coffee = url("https://buymeacoffee.com/sageframe")

    /// Builds a `URL` from a compile-time-constant literal that is always valid.
    ///
    /// The fallback is never reached for these literals; it only spares a force
    /// unwrap.
    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}
