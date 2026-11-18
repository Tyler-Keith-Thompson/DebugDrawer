// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    import Testing

    /// The exit tests that install the swizzles in a child, one suite per file. Each child keeps
    /// its spoofing state in its own argument domain, so none sees another's.
    @Suite(.timeLimit(.minutes(1)))
    struct LocationSwizzleExitTests {}
#endif
