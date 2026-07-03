// PalanaCore: headless library for pālana.
//
// All truth, all logic, the 90% coverage floor lives here. The seven
// components (Conduit, Field, Listing, Plan Engine, Transports, Workbench)
// arrive with their hos. Surfaced via the Palana (SwiftUI) executable.

/// Namespace for the pālana core library.
///
/// Holds the public API surface and shared utilities. Instantiation is
/// not supported (cases-less enum).
public enum PalanaCore {
    /// Library version.
    ///
    /// Bumped at release tags. Surfaced by the app's About surface.
    public static let version = "0.1.0"
}
