/// A named action a plugin offers to the drawer's search field, run when the user picks it.
///
/// The type exists in every build so a plugin's `actions` compile unchanged in release, where the
/// drawer, and so the search field, doesn't exist.
public struct DebugDrawerAction: Identifiable {
    /// The name shown in the results, and matched against what the user types.
    public let title: String
    /// Other words the action is found by ("clear", "reset").
    public let keywords: [String]
    /// Runs the action.
    public let perform: @MainActor () -> Void

    /// The title identifies the action among its plugin's actions.
    public var id: String { title }

    /// An action titled `title`, found by its title or any of `keywords`, that runs `perform`.
    public init(_ title: String, keywords: [String] = [], perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.keywords = keywords
        self.perform = perform
    }
}
