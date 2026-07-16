// PalanaSession+Onboarding — the first-reach probe offered after a
// guided add. Extracted from PalanaSession.swift to keep that file
// within the line-length budget (ho-11 made room by moving this one
// self-contained extension out, alongside the +ZFS and +DragDrop
// precedent).

import PalanaCore

extension PalanaSession {
    /// First-reach probe offered after a guided add.
    func probeHost(alias: String) async -> OnboardingProbeOutcome {
        guard alias != Engine.localHost else { return .connected }
        guard let facts = try? await sessionEngine.field.discover(alias),
            case .unreachable(let detail) = facts.reachability?.value
        else { return .connected }
        let low = detail.lowercased()
        let denied = low.contains("authentication denied") || low.contains("permission denied")
        return denied ? .authDenied(detail: detail) : .unreachable(detail: detail)
    }
}
