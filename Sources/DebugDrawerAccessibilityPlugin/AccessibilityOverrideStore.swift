#if DEBUG
    import Combine
    import Foundation

    /// Where the overrides the plugin edits live: ``AccessibilityOverrides/shared``, which
    /// `.debugAccessibilityOverrides()` applies, in the app.
    @MainActor
    protocol AccessibilityOverrideStore: AnyObject {
        /// The overrides now. Setting it changes only the values that differ.
        var values: AccessibilityOverrideValues { get set }
        /// The identifiers of the locales the app is localized into, sorted ("de", "fr").
        var localeIdentifiers: [String] { get }
        /// Fires before ``values`` changes.
        var changes: AnyPublisher<Void, Never> { get }
    }
#endif
