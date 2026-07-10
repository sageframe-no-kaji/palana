// PaneHistory — per-pane back/forward navigation stack, session-lifetime,
// not persisted. Browser semantics: new navigation clears the forward stack.

/// A location in a pane's history.
public struct PaneLocation: Equatable, Sendable {
    /// The host alias.
    public let host: String
    /// The absolute path.
    public let path: String

    /// Creates a location.
    public init(host: String, path: String) {
        self.host = host
        self.path = path
    }
}

/// A session-lifetime back/forward stack for one pane.
///
/// Browser semantics: pushing a new location clears the forward stack.
/// ``back()`` and ``forward()`` are no-ops when their respective stacks
/// are empty.
public struct PaneHistory: Sendable {
    /// The entries available to navigate back through.
    public private(set) var backStack: [PaneLocation] = []
    /// The entries available to navigate forward through.
    public private(set) var forwardStack: [PaneLocation] = []

    /// Creates an empty history.
    public init() {}

    /// Whether ``back(current:)`` has anywhere to go.
    public var canGoBack: Bool { !backStack.isEmpty }
    /// Whether ``forward(current:)`` has anywhere to go.
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Pushes the current location onto the back stack and clears the forward stack.
    ///
    /// Call this when a navigation commits to a location different from the current one.
    public mutating func push(_ location: PaneLocation) {
        backStack.append(location)
        forwardStack = []
    }

    /// Pops the top of the back stack and returns it, pushing the current location
    /// onto the forward stack.
    ///
    /// Returns nil when the back stack is empty.
    public mutating func back(current: PaneLocation) -> PaneLocation? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        return previous
    }

    /// Pops the top of the forward stack and returns it, pushing the current location
    /// onto the back stack.
    ///
    /// Returns nil when the forward stack is empty.
    public mutating func forward(current: PaneLocation) -> PaneLocation? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        return next
    }
}
