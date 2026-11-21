#if DEBUG
    import Testing

    // The suites that change DebugDrawer.shared, which the plugin's view falls back to outside any
    // drawer, nest in this one, in extensions beside the suites of their files. Serialized, which
    // holds for every suite nested in it, so no two of them change the shared drawer at once. Every
    // other suite makes a drawer of its own and runs alongside the rest.
    @Suite("The shared drawer", .serialized)
    enum SharedDrawerTests {}
#endif
