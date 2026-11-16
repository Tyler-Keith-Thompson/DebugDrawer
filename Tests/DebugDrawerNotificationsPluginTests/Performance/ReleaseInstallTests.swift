// The release stand-ins. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and NotificationsInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerNotificationsPlugin
    import Foundation
    import MachO
    import Testing

    @Suite
    struct ReleaseInstallTests {
        /// What a registration failure reports.
        struct RegistrationFailed: Error {}

        @MainActor
        @Test("In release, every call compiles, and the binary they are linked into doesn't link User Notifications")
        func installLinksNothing() throws {
            // The plugin is linked statically into this test's executable, as into an app, so the
            // executable's own load commands say what it added. AppKit and SwiftUI may load User
            // Notifications themselves, so what the process has loaded would say nothing.
            let header = try #require(_dyld_get_image_header(0))

            PushNotifications.install()
            PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: Data([0xAB, 0xCD]))
            PushNotifications.didFailToRegisterForRemoteNotifications(withError: RegistrationFailed())
            var linked: [String] = []
            var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0 ..< header.pointee.ncmds {
                let load = command.load(as: load_command.self)
                if load.cmd == LC_LOAD_DYLIB || load.cmd == LC_LOAD_WEAK_DYLIB {
                    let dylib = command.load(as: dylib_command.self)
                    linked.append(String(cString: command.advanced(by: Int(dylib.dylib.name.offset)).assumingMemoryBound(to: CChar.self)))
                }
                command = command.advanced(by: Int(load.cmdsize))
            }
            let actual = linked.filter { $0.contains("/UserNotifications.framework/") }

            #expect(linked.contains { $0.contains("/SwiftUI.framework/") })
            #expect(actual.isEmpty)
        }
    }
#endif
