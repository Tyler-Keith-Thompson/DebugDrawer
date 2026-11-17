#if DEBUG
    import SwiftUI

    // MARK: - Conditional environment modifier

    /// Overrides an environment value when `value` is non-nil and leaves the inherited
    /// (system) value alone when it is nil.
    ///
    /// The view tree has the same shape either way: an `if let` here would be a
    /// conditional branch, so the host's subtree would get a new identity, losing its
    /// `@State` and navigation, each time an override went between nil and a value.
    private struct ConditionalEnvironment<V: Sendable>: ViewModifier {
        let keyPath: WritableKeyPath<EnvironmentValues, V>
        let value: V?

        init(_ keyPath: WritableKeyPath<EnvironmentValues, V>, value: V?) {
            self.keyPath = keyPath
            self.value = value
        }

        func body(content: Content) -> some View {
            content.transformEnvironment(keyPath) { [value] current in
                if let value { current = value }
            }
        }
    }

    // MARK: - Override state

    @MainActor
    public final class AccessibilityOverrides: ObservableObject {
        public static let shared = AccessibilityOverrides()

        @Published public var colorScheme: ColorScheme?
        @Published public var dynamicTypeSize: DynamicTypeSize?
        @Published public var layoutDirection: LayoutDirection?
        @Published public var locale: Locale?
        /// System accessibility settings; nil means the system's value is used.
        @Published public var reduceMotion: Bool?
        @Published public var increaseContrast: Bool?
        @Published public var boldText: Bool?
        @Published public var reduceTransparency: Bool?
        @Published public var differentiateWithoutColor: Bool?
        @Published public var invertColors: Bool?

        /// Available localizations discovered from the app bundle.
        public let availableLocales: [Locale]

        private init() {
            let ids = Bundle.main.localizations
                .filter { $0 != "Base" }
                .sorted()
            availableLocales = ids.map { Locale(identifier: $0) }
        }

        public func reset() {
            colorScheme = nil
            dynamicTypeSize = nil
            layoutDirection = nil
            locale = nil
            reduceMotion = nil
            increaseContrast = nil
            boldText = nil
            reduceTransparency = nil
            differentiateWithoutColor = nil
            invertColors = nil
        }

        public var hasOverrides: Bool {
            colorScheme != nil || dynamicTypeSize != nil ||
                layoutDirection != nil || locale != nil ||
                reduceMotion != nil || increaseContrast != nil || boldText != nil ||
                reduceTransparency != nil || differentiateWithoutColor != nil || invertColors != nil
        }
    }

    // MARK: - Environment modifier

    public struct AccessibilityOverridesModifier: ViewModifier {
        @ObservedObject private var overrides = AccessibilityOverrides.shared

        public init() {}

        public func body(content: Content) -> some View {
            // Every modifier is always applied, so the host's view tree keeps its shape
            // (and its state) whether or not an override is set.
            let modified = content
                .modifier(ConditionalEnvironment(\.dynamicTypeSize, value: overrides.dynamicTypeSize))
                .modifier(ConditionalEnvironment(\.layoutDirection, value: overrides.layoutDirection))
                .modifier(ConditionalEnvironment(\.locale, value: overrides.locale))
                // The public keys are get-only; SwiftUI reads them from these settable
                // underscored keys, which are what previews use to force a value.
                .modifier(ConditionalEnvironment(\._accessibilityReduceMotion, value: overrides.reduceMotion))
                .modifier(ConditionalEnvironment(\._colorSchemeContrast,
                                                 value: overrides.increaseContrast.map { $0 ? .increased : .standard }))
                // legibilityWeight is itself optional: wrap explicitly so "no override"
                // stays nil instead of becoming an override to nil.
                .modifier(ConditionalEnvironment(\.legibilityWeight,
                                                 value: overrides.boldText.map { Optional($0 ? LegibilityWeight.bold : .regular) }))
                .modifier(ConditionalEnvironment(\._accessibilityReduceTransparency, value: overrides.reduceTransparency))
                .modifier(ConditionalEnvironment(\._accessibilityDifferentiateWithoutColor,
                                                 value: overrides.differentiateWithoutColor))
                .modifier(ConditionalEnvironment(\._accessibilityInvertColors, value: overrides.invertColors))
                .preferredColorScheme(overrides.colorScheme)
            return modified
        }
    }

    public extension View {
        func debugAccessibilityOverrides() -> some View {
            modifier(AccessibilityOverridesModifier())
        }
    }
#else
    import SwiftUI

    // The release stand-ins: the same members, so the host's code compiles unchanged, and no
    // overrides behind them. Every value stays nil and the modifier changes nothing.

    /// Release builds override nothing: this stand-in keeps the debug build's members.
    @MainActor
    public final class AccessibilityOverrides: ObservableObject {
        /// The stand-in overrides.
        public static let shared = AccessibilityOverrides()

        /// Always nil unless set; nothing reads it.
        @Published public var colorScheme: ColorScheme?
        /// Always nil unless set; nothing reads it.
        @Published public var dynamicTypeSize: DynamicTypeSize?
        /// Always nil unless set; nothing reads it.
        @Published public var layoutDirection: LayoutDirection?
        /// Always nil unless set; nothing reads it.
        @Published public var locale: Locale?
        /// Always nil unless set; nothing reads it.
        @Published public var reduceMotion: Bool?
        /// Always nil unless set; nothing reads it.
        @Published public var increaseContrast: Bool?
        /// Always nil unless set; nothing reads it.
        @Published public var boldText: Bool?
        /// Always nil unless set; nothing reads it.
        @Published public var reduceTransparency: Bool?
        /// Always nil unless set; nothing reads it.
        @Published public var differentiateWithoutColor: Bool?
        /// Always nil unless set; nothing reads it.
        @Published public var invertColors: Bool?

        /// Always empty.
        public let availableLocales: [Locale] = []

        private init() {}

        /// Does nothing.
        public func reset() {}

        /// Always false.
        public var hasOverrides: Bool {
            false
        }
    }

    /// Returns the content unchanged: release builds override nothing.
    public struct AccessibilityOverridesModifier: ViewModifier {
        /// The stand-in modifier.
        public init() {}

        /// Returns `content` unchanged.
        public func body(content: Content) -> some View {
            content
        }
    }

    public extension View {
        func debugAccessibilityOverrides() -> some View { self }
    }
#endif
