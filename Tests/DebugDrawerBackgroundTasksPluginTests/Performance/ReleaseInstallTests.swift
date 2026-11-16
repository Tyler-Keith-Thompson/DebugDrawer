// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and BackgroundTasksInstallExitTests checks the opposite. On the Mac the debug build
// links no BackgroundTasks either (its types are unavailable there), so this pins that the call
// compiles and that the stand-in adds no framework; the iOS release build was checked with
// `otool -L` on the example app.
#if !DEBUG
    import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import MachO
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install compiles, and the binary it is linked into doesn't link BackgroundTasks")
        func installLinksNothing() throws {
            // The plugin is linked statically into this test's executable, as into an app, so the
            // executable's own load commands say what it added.
            let header = try #require(_dyld_get_image_header(0))

            BackgroundTaskRequests.install()
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
            let actual = linked.filter { $0.contains("/BackgroundTasks.framework/") }

            #expect(linked.contains { $0.contains("/Foundation.framework/") })
            #expect(actual.isEmpty)
        }
    }
#endif
