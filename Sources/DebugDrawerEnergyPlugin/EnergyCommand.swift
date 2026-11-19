import Foundation

// Public because it is `EnergyMonitor`'s `Command`, and opaque: an enum's cases share its access
// level, so the public type is a struct around the internal enum. Showing and hiding the plugin
// aren't commands: the drawer's lifecycle hooks count its viewers, and a reader elsewhere asks for
// samples with `start` and lets go with `stop`, as the app does.

#if DEBUG
    /// Something asked of ``EnergyMonitor``: sample, stop sampling, or start the history over.
    /// `Codable`, so a transport can carry it.
    public struct EnergyCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Samples once a second until `stop`, as the app's `start()` does.
            case start
            /// Ends what `start` began; sampling goes on while a drawer shows the plugin.
            case stop
            /// Empties the CPU and battery history; the latest readings stay.
            case reset
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds sample nothing: this stand-in asks for nothing.
    public struct EnergyCommand: Codable, Sendable {}
#endif
