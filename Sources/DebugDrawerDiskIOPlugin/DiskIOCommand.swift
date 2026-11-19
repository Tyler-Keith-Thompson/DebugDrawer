import Foundation

// Public because it is `DiskIOModel`'s `Command`, and opaque: an enum's cases share its access
// level, so the public type is a struct around the internal enum.

#if DEBUG
    /// Something the Disk I/O plugin's view asks ``DiskIOModel`` to do: filter the list, clear it,
    /// pause or resume recording, or read the volume again. `Codable`, so a transport can carry it.
    public struct DiskIOCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Lists only the calls of the operation, or of every operation for `nil`.
            case setOperation(IOEvent.Operation?)
            /// Lists only the calls made on the main thread, or every call.
            case setMainThreadOnly(Bool)
            /// Forgets the recorded calls and starts the totals over.
            case clear
            /// Pauses recording, or resumes it.
            case setPaused(Bool)
            /// Reads the volume's size and free space again.
            case refreshVolume
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds record no disk I/O: this stand-in asks for nothing.
    public struct DiskIOCommand: Codable, Sendable {}
#endif
