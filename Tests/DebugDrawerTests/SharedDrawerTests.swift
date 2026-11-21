#if DEBUG
    import Testing

    // The suites whose subject is DebugDrawer.shared itself, or a convenience bound to it
    // (`debugDrawer()`, `debugLocalPlugin(_:)`, a plugin's `setBadge(_:)` and `postToast(_:)`, the
    // README's and the DocC articles' examples, which call the shared drawer), and the few tests
    // production code sends to the shared drawer, nest in this one, in extensions beside the
    // suites of their files. Serialized, which holds for every suite nested in it, so no two of
    // them run at once and none sees another's plugins, windows or toasts. Every other suite makes
    // a drawer of its own and runs alongside the rest.
    @Suite("The shared drawer", .serialized)
    enum SharedDrawerTests {}
#endif
