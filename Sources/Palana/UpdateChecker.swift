// UpdateChecker — the launch-time update signal (ho-12, the M4Bookmaker shape).
//
// One outbound call, on launch, opt-out: pālana asks GitHub for the latest
// release tag and — if it's newer than the running build — announces it with a
// link to the release page. It never installs anything; the operator clicks
// through. Consistent with bīja: opt-out (`checkForUpdates`), launch-only (no
// poll), transparent (Settings shows the toggle and the result). A dev build
// (no bundle version) is a quiet no-op, so `swift run` never shows a false
// "update available". The version compare is PalanaCore's pinned ReleaseVersion.

import Foundation
import Observation
import PalanaCore

/// The update-availability signal and its GitHub check.
@MainActor
@Observable
final class UpdateChecker {
    /// A newer release than the one running.
    struct Available: Equatable {
        /// The release tag, e.g. `v1.1`.
        let version: String
        /// Where to get it — the product site (the binary is on Payhip; the
        /// site is the hub), not a GitHub download.
        let url: URL
    }

    /// The newer release, if one was found; `nil` when up to date or unchecked.
    private(set) var available: Available?
    /// When the last check completed — shown quietly in Settings.
    private(set) var lastChecked: Date?
    /// True while a check is in flight.
    private(set) var checking = false

    /// The opt-out key — absent reads as on (checking is the default).
    static let storageKey = "checkForUpdates"
    /// The public repo the check reads.
    static let repoSlug = "sageframe-no-kaji/palana"

    /// Whether the launch check is enabled (default on).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? true
    }

    /// The running build's version, or `nil` in a dev build with no bundle.
    var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// The launch check — a quiet no-op when opted out.
    func checkIfEnabled() async {
        guard isEnabled else { return }
        await check()
    }

    /// One check against GitHub's latest release, ignoring the opt-out.
    ///
    /// The "Check now" button calls this directly. A dev build with no version
    /// is skipped so it never announces a phantom update.
    func check() async {
        guard let current = currentVersion else { return }
        checking = true
        defer {
            checking = false
            lastChecked = Date()
        }
        guard let tag = await Self.fetchLatestTag() else { return }
        available =
            ReleaseVersion.isNewer(tag, than: current)
            ? Available(version: tag, url: Links.website) : nil
    }

    /// Fetches the latest release's tag from GitHub, or `nil` on any failure.
    ///
    /// Reads only the version — where to *get* the update is the site
    /// (``Links/website``), since the binary is sold on Payhip. An update check
    /// that can't reach GitHub is silent, never an error. Requires a published
    /// GitHub Release per version (notes only; no binary attached).
    private static func fetchLatestTag() async -> String? {
        guard let endpoint = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest")
        else { return nil }
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
        else { return nil }
        return release.tagName
    }
}

/// The slice of GitHub's release JSON the check reads.
private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
