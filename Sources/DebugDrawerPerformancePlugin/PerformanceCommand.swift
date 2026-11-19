import Foundation

// Public because it is `PerformanceModel`'s `Command`, and opaque: an enum's cases share its access
// level, so the public type is a struct around the internal enum. Start and stop count viewers, as
// the plugin's lifecycle hooks do, so a reader that asks to sample can't stop a drawer's sampling
// or keep it running past its own stop.

#if DEBUG
    /// Something asked of ``PerformanceModel``: to sample while a reader watches and stop after,
    /// drop the history, keep a longer or shorter history, or post a memory warning. `Codable`,
    /// so a transport can carry it.
    public struct PerformanceCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Counts one more viewer; the first starts sampling.
            case start
            /// Uncounts a viewer; the last stops sampling. Does nothing with none counted.
            case stop
            /// Drops the frame and memory history and the frames counted as dropped; sampling,
            /// if running, carries on from the next second.
            case reset
            /// Keeps this many seconds of history, at least one, dropping the oldest samples
            /// beyond it.
            case setHistoryLength(Int)
            /// Posts the memory warning to the app's observers, where the platform has one.
            case simulateMemoryWarning
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds sample nothing: this stand-in asks for nothing.
    public struct PerformanceCommand: Codable, Sendable {}
#endif
