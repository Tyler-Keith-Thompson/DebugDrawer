// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone. They read suites but
// write none.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    @Suite("UserDefaults install, in a child process")
    struct UserDefaultsInstallExitTests {
        @Test("Install registers the plugin, offering Standard and the suites named, in their order")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    UserDefaultsBrowser.install(suites: ["group.b", "group.a"])
                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "UserDefaults" }
                        && UserDefaultsModel.shared.snapshot.suites == [.standard, .named("group.b"), .named("group.a")]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once, over the suites named last")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    UserDefaultsBrowser.install()
                    UserDefaultsBrowser.install(suites: ["group.a"])
                    return DebugDrawer.shared.globalPlugins.filter { $0.title == "UserDefaults" }.count == 1
                        && UserDefaultsModel.shared.snapshot.suites == [.standard, .named("group.a")]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: UserDefaults")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                await MainActor.run {
                    // At startup:
                    UserDefaultsBrowser.install(suites: ["group.com.example.shared"])

                    let plugins = DebugDrawer.shared.globalPlugins.filter { $0.title == "UserDefaults" }
                    exit(plugins.count == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }
#endif
