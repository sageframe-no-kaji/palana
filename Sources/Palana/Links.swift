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

    /// Filing a bug — the public issue tracker.
    static let reportBug = url("https://github.com/sageframe-no-kaji/palana/issues/new")

    /// Support the work — the "Buy Me a Coffee" page.
    ///
    /// TODO(ho-12): swap the placeholder for the real page — points at the site
    /// until then, so the menu item never opens a dead link.
    static let coffee = url("https://palana.sageframe.net")

    /// Builds a `URL` from a compile-time-constant literal that is always valid.
    ///
    /// The fallback is never reached for these literals; it only spares a force
    /// unwrap.
    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}
