/// A titled group of tweaks and actions, shown together in the drawer in the order declared.
///
/// ```swift
/// TweakSection("Server") {
///     AppTweaks.environment
///     AppTweaks.timeout
///     TweakAction("Expire token") { session.expireToken() }
/// }
/// ```
///
/// The type exists in every build so a declaration compiles unchanged in release.
public struct TweakSection: Sendable {
    /// The section's heading.
    public let title: String
    let items: [TweakItem]

    /// A section titled `title` holding what `items` lists.
    public init(_ title: String, @TweakItemBuilder _ items: () -> [TweakItem]) {
        self.title = title
        self.items = items()
    }
}

/// One entry of a ``TweakSection``: a ``Tweak`` or a ``TweakAction``, as ``TweakItemBuilder``
/// makes it.
public struct TweakItem: Sendable {
    enum Kind: Sendable {
        case tweak(AnyTweak)
        case action(TweakAction)
    }

    let kind: Kind
}

/// Lists a section's tweaks and actions, one per line, with `if`, `switch` and `for` as in a
/// view builder.
@resultBuilder
public enum TweakItemBuilder {
    public static func buildExpression<Value>(_ tweak: Tweak<Value>) -> [TweakItem] {
        [TweakItem(kind: .tweak(AnyTweak(tweak)))]
    }

    public static func buildExpression(_ action: TweakAction) -> [TweakItem] {
        [TweakItem(kind: .action(action))]
    }

    public static func buildBlock(_ components: [TweakItem]...) -> [TweakItem] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [TweakItem]?) -> [TweakItem] {
        component ?? []
    }

    public static func buildEither(first component: [TweakItem]) -> [TweakItem] {
        component
    }

    public static func buildEither(second component: [TweakItem]) -> [TweakItem] {
        component
    }

    public static func buildArray(_ components: [[TweakItem]]) -> [TweakItem] {
        components.flatMap(\.self)
    }
}

/// Lists the sections of the Tweaks plugin, in the order shown, with `if`, `switch` and `for` as
/// in a view builder.
@resultBuilder
public enum TweakSectionBuilder {
    public static func buildExpression(_ section: TweakSection) -> [TweakSection] {
        [section]
    }

    public static func buildBlock(_ components: [TweakSection]...) -> [TweakSection] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [TweakSection]?) -> [TweakSection] {
        component ?? []
    }

    public static func buildEither(first component: [TweakSection]) -> [TweakSection] {
        component
    }

    public static func buildEither(second component: [TweakSection]) -> [TweakSection] {
        component
    }

    public static func buildArray(_ components: [[TweakSection]]) -> [TweakSection] {
        components.flatMap(\.self)
    }
}
