import SwiftUI

// The one SwiftUI piece of the module, in it rather than a module of its own or the host's: the
// overrides change nothing until a view's environment holds them, the modifier only sets
// environment values and draws nothing, and every host would otherwise write the same one,
// including the underscored keys below. Every modifier is always applied, so the host's view tree
// keeps its shape, and its state, whether or not an override is set.
//
// Increase Contrast and Reduce Motion are get-only in SwiftUI's environment; SwiftUI reads them
// from the settable underscored keys `_colorSchemeContrast` and `_accessibilityReduceMotion`, which
// are public in SwiftUI's module interface (not SPI) and what Xcode's previews set to force a
// value. The Accessibility plugin's `debugAccessibilityOverrides()` sets the same keys.

public extension View {
    /// Applies `overrides` to this view and the views under it: each of Dynamic Type, Increase
    /// Contrast and Reduce Motion that a sidecar overrode during its session, and the system's value
    /// for the rest, and for all of them once the session ends.
    ///
    /// Apply it to the app's root view:
    ///
    /// ```swift
    /// ContentView()
    ///     .accessibilityEnvironmentOverrides()
    /// ```
    ///
    /// SwiftUI views read the overrides through their environment (`dynamicTypeSize`,
    /// `colorSchemeContrast`, `accessibilityReduceMotion`); UIKit and AppKit views read the
    /// system's settings and don't see them.
    ///
    /// - Parameter overrides: The overrides to apply; ``AccessibilityEnvironmentOverrides/shared``
    ///   unless given.
    /// - Returns: The view with the overrides in its environment.
    func accessibilityEnvironmentOverrides(_ overrides: AccessibilityEnvironmentOverrides = .shared) -> some View {
        modifier(EnvironmentOverridesModifier(overrides: overrides))
    }
}

/// Sets each overridden value in the content's environment.
private struct EnvironmentOverridesModifier: ViewModifier {
    @ObservedObject var overrides: AccessibilityEnvironmentOverrides

    func body(content: Content) -> some View {
        let snapshot = overrides.snapshot
        let dynamicTypeSize = snapshot.dynamicTypeSize.map(SwiftUI.DynamicTypeSize.init)
        let contrast = snapshot.increaseContrast.map { $0 ? ColorSchemeContrast.increased : .standard }
        let reduceMotion = snapshot.reduceMotion
        return content
            .transformEnvironment(\.dynamicTypeSize) { value in
                if let dynamicTypeSize { value = dynamicTypeSize }
            }
            .transformEnvironment(\._colorSchemeContrast) { value in
                if let contrast { value = contrast }
            }
            .transformEnvironment(\._accessibilityReduceMotion) { value in
                if let reduceMotion { value = reduceMotion }
            }
    }
}

extension SwiftUI.DynamicTypeSize {
    /// SwiftUI's size for `size`: both list the same twelve sizes, smallest first.
    fileprivate init(_ size: AccessibilityEnvironmentOverrides.DynamicTypeSize) {
        // The force unwrap can't fire: a case is always in its own type's `allCases`. The index is
        // in SwiftUI's list, which holds the same twelve sizes in the same order; the tests check
        // each size by name.
        let index = AccessibilityEnvironmentOverrides.DynamicTypeSize.allCases.firstIndex(of: size)!
        self = Self.allCases[index]
    }
}
