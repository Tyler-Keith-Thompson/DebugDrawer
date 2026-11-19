#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Foundation

    /// The device the app runs on, from `ProcessInfo`, `uname` and the screen.
    struct _DeviceInfoSource: DeviceInfoSource {
        func read() -> DeviceInfo {
            let process = ProcessInfo.processInfo
            #if os(macOS)
                // iOS, tvOS, watchOS and visionOS apps are always sandboxed, and don't get this variable.
                let isSandboxed: Bool? = process.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            #else
                let isSandboxed: Bool? = nil
            #endif
            return DeviceInfo(
                operatingSystemName: Self.operatingSystemName,
                operatingSystemVersion: process.operatingSystemVersionString,
                isSandboxed: isSandboxed,
                activeProcessorCount: process.activeProcessorCount,
                physicalMemory: process.physicalMemory,
                screen: Self.screen,
                architecture: process.machineHardwareName
            )
        }

        /// The OS row's label. The same names as core's bug-report summary, written out again
        /// here because core's are private to it, not part of the plugin contract.
        static var operatingSystemName: String {
            #if os(macOS)
                "macOS"
            #elseif targetEnvironment(macCatalyst)
                // ProcessInfo reports the Mac's macOS version, not an iOS one, under Catalyst.
                "macOS (Mac Catalyst)"
            #elseif os(visionOS)
                "visionOS"
            #elseif os(tvOS)
                "tvOS"
            #elseif os(watchOS)
                "watchOS"
            #else
                "iOS"
            #endif
        }

        private static var screen: DeviceInfo.Screen? {
            #if os(macOS)
                guard let screen = NSScreen.main else { return nil }
                return DeviceInfo.Screen(width: screen.frame.size.width, height: screen.frame.size.height, scale: screen.backingScaleFactor)
            #elseif os(iOS)
                // The screen of the foreground window scene (UIScreen.main is deprecated).
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
                else { return nil }
                return DeviceInfo.Screen(width: screen.bounds.size.width, height: screen.bounds.size.height, scale: screen.scale)
            #else
                return nil
            #endif
        }
    }

    extension ProcessInfo {
        var machineHardwareName: String {
            var sysinfo = utsname()
            uname(&sysinfo)
            return withUnsafeBytes(of: &sysinfo.machine) { buf in
                String(cString: buf.bindMemory(to: CChar.self).baseAddress!)
            }
        }
    }
#endif
