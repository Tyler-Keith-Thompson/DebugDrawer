import Foundation

// Public because it is `LaunchTimeModel`'s `Command`, and opaque: an enum's cases share its access
// level, so the public type is a struct around the internal enum.

#if DEBUG
    /// Something asked of ``LaunchTimeModel``: for now, to take the first frame as in.
    /// `Codable`, so a transport can carry it.
    public struct LaunchTimeCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Sendable {
            /// Records the first frame as in now, unless one already is, and stops waiting for
            /// the main run loop: for a reader that knows the frame it measures to better than
            /// the run loop's first idle (a splash screen, a first screen drawn once its data
            /// loads).
            case recordFirstFrame
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds measure nothing: this stand-in asks for nothing.
    public struct LaunchTimeCommand: Codable, Sendable {}
#endif
