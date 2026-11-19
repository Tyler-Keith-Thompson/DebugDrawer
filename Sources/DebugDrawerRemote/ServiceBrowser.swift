import Network

// The browser's seam to the network, so a test can see that nothing browses until the viewer
// asks, and what a result becomes, without browsing this Mac's network.

#if DEBUG
    /// One service a browse found: its name, where it is, and its TXT record.
    struct BrowsedService: Equatable, Sendable {
        var name: String
        var endpoint: NWEndpoint
        var txtRecord: [String: String]
    }

    /// Browses the local network for ``DebugDrawerBonjourService/type`` services.
    @MainActor
    protocol ServiceBrowser: AnyObject {
        /// Starts browsing, calling `results` on the main actor with every service found each
        /// time the set changes. Called again only after ``cancel()``.
        func start(_ results: @escaping @MainActor ([BrowsedService]) -> Void)

        /// Stops browsing.
        func cancel()
    }
#endif
