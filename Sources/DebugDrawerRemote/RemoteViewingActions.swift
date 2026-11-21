#if DEBUG
    /// What the Remote Viewing plugin's buttons do.
    @MainActor
    struct RemoteViewingActions {
        /// Start Serving.
        let start: () -> Void
        /// Stop Serving.
        let stop: () -> Void
        /// Reject, for one viewer asking to pair.
        let reject: (DebugDrawerPairingRequest) -> Void
        /// Disconnect, for one paired viewer.
        let disconnect: (DebugDrawerPairedViewer) -> Void
    }
#endif
