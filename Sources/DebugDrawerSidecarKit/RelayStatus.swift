#if DEBUG && canImport(DebugDrawerRemote)
    import DebugDrawer
    import Foundation

    /// The relay's own model, served under ``DebugDrawerSidecarRelay/pluginID``: what a viewer
    /// reads of the relay. It takes no command.
    @MainActor
    final class RelayStatus: DebugDrawerPluginModel {
        @Published var snapshot: DebugDrawerSidecarRelay.Snapshot

        init(snapshot: DebugDrawerSidecarRelay.Snapshot) {
            self.snapshot = snapshot
        }

        func perform(_ command: Never) {}
    }
#endif
