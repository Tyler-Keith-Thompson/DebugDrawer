#if DEBUG
    import Testing

    /// Every suite that installs the View Inspector plugin in this process, or reads counts from
    /// the shared tracker, is nested in this one. `.trackRenders(_:)` counts into the tracker of
    /// the drawer that installed the plugin last, so these take turns: no test's install takes the
    /// counts from another's while it waits for them.
    @Suite(.serialized)
    enum RenderTrackingInstalls {}
#endif
