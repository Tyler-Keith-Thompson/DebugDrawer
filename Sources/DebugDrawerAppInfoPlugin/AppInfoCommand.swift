import Foundation

// Public because it is `AppInfoModel`'s `Command`, and opaque: an enum's cases share its access
// level, so the public type is a struct around the internal enum. Start and stop count viewers, as
// the plugin's lifecycle hooks do, so a reader that asks to refresh can't stop a drawer's
// refreshing or keep it running past its own stop. Copy Info stays in the view.

#if DEBUG
    /// Something asked of ``AppInfoModel``: to refresh every 2 seconds while a reader watches and
    /// stop after, or to read the facts again now. `Codable`, so a transport can carry it.
    public struct AppInfoCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Counts one more viewer; the first reads the facts now and every 2 seconds after.
            case start
            /// Uncounts a viewer; the last stops the refreshing. Does nothing with none counted.
            case stop
            /// Reads the facts now, once, refreshing or not.
            case refresh
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds read nothing: this stand-in asks for nothing.
    public struct AppInfoCommand: Codable, Sendable {}
#endif
