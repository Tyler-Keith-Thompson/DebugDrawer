#if DEBUG
    /// Reads the app's key window's view hierarchy into values.
    ///
    /// The View Inspector's model takes it at init; `_ViewHierarchyReader` walks the app's real
    /// views, and a test passes one that returns a fixture.
    @MainActor
    protocol ViewHierarchyReader {
        /// The hierarchy under the app's key window's root view, or `nil` when the app has no key
        /// window, or one without a root view.
        func keyWindowHierarchy() -> ViewNode?
    }
#endif
