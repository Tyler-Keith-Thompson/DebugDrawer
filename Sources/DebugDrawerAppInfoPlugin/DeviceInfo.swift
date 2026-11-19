#if DEBUG
    import Foundation

    /// The device and operating system the app runs on, as App Info shows them.
    struct DeviceInfo: Codable, Equatable, Sendable {
        /// A screen's size in points and its scale.
        struct Screen: Codable, Equatable, Sendable {
            var width: Double
            var height: Double
            var scale: Double
        }

        /// The platform's name ("macOS", "iOS", "macOS (Mac Catalyst)"), the OS row's label.
        var operatingSystemName = ""
        /// `ProcessInfo.operatingSystemVersionString`.
        var operatingSystemVersion = ""
        /// Whether the app runs in the App Sandbox; `nil` where every app does and the system
        /// doesn't say, as on iOS.
        var isSandboxed: Bool?
        /// The processor cores the system lets the app use.
        var activeProcessorCount = 0
        /// The device's memory, in bytes.
        var physicalMemory: UInt64 = 0
        /// The screen the app is on, or `nil` when there is none to read.
        var screen: Screen?
        /// The machine's hardware name (`utsname.machine`), such as `arm64`.
        var architecture = ""
    }
#endif
