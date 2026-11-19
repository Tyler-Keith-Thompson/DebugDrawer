#if DEBUG
    import Foundation

    /// Where App Info reads the device and operating system: `ProcessInfo`, `uname` and the
    /// screen.
    ///
    /// The App Info model takes it at init; `_DeviceInfoSource` asks the system, and a test passes
    /// one that returns what it chooses. Main-actor isolated, as the screen is read there.
    @MainActor
    protocol DeviceInfoSource {
        /// The device and operating system now.
        func read() -> DeviceInfo
    }
#endif
