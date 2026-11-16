/// A button the host declares in a ``TweakSection``, which runs its closure when pressed:
/// "Reset onboarding", "Expire token". It stores nothing.
///
/// The drawer's search field finds it too, by its title or its section's.
///
/// The type exists in every build so a section compiles unchanged in release, where there is no
/// drawer and nothing runs it.
public struct TweakAction: Sendable {
    /// The button's title, which names what it does.
    public let title: String
    /// Runs the action.
    public let perform: @MainActor @Sendable () -> Void

    /// An action titled `title` that runs `perform` when pressed.
    public init(_ title: String, perform: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.perform = perform
    }
}
