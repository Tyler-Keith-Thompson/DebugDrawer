// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, and uninstalling puts it back, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    @testable import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import ObjectiveC
    import Testing

    /// A method other code swaps in on top of the plugin's, which calls whatever it replaced.
    extension FileManager {
        @objc fileprivate func onTopContents(atPath path: String) -> NSData? {
            onTopContents(atPath: path)
        }
    }

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOUninstallExitTests {
        @Test("Removing the plugin puts back each original method, records nothing more and forgets the calls; a reinstall records again")
        func uninstallRestoresOriginals() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func implementations() throws -> [IMP] {
                    let handleClass: AnyClass = try #require(object_getClass(FileHandle(fileDescriptor: STDERR_FILENO, closeOnDealloc: false)))
                    let methods = try [
                        #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.contents(atPath:)))),
                        #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.dd_contents(atPath:)))),
                        #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.removeItem(at:)))),
                        #require(class_getInstanceMethod(NSData.self, #selector(NSData.write(toFile:atomically:)))),
                        #require(class_getInstanceMethod(NSData.self, NSSelectorFromString("initWithContentsOfFile:"))),
                        #require(class_getInstanceMethod(NSData.self, NSSelectorFromString("initWithContentsOfURL:options:error:"))),
                        #require(class_getInstanceMethod(handleClass, NSSelectorFromString("writeData:")))
                    ]
                    return methods.map(method_getImplementation)
                }

                @MainActor
                func waitUntilRecorded(_ name: String) async {
                    for await events in DiskIOStore.shared.$events.values where events.contains(where: { $0.path.hasSuffix(name) }) {
                        break
                    }
                }

                @MainActor
                func uninstallThenReinstall() async throws {
                    let suite = "DiskIOUninstallExitTests.\(UUID().uuidString)"
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let directory = FileManager.default.temporaryDirectory.appending(path: "DiskIOUninstall-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let expected = try implementations()

                    drawer.installDiskIO()
                    let whileInstalled = try implementations()
                    _ = FileManager.default.createFile(atPath: directory.appending(path: "installed").path, contents: Data("1".utf8))
                    await waitUntilRecorded("/installed")
                    drawer.unregisterGlobal(id: DiskIOPlugin().id)
                    let actual = try implementations()
                    let keptAfterUninstall = DiskIOStore.shared.events.count
                    _ = FileManager.default.createFile(atPath: directory.appending(path: "uninstalled").path, contents: Data("2".utf8))
                    _ = FileManager.default.contents(atPath: directory.appending(path: "uninstalled").path)
                    drawer.unregisterGlobal(id: DiskIOPlugin().id)
                    let afterSecondUninstall = try implementations()

                    drawer.installDiskIO()
                    _ = FileManager.default.createFile(atPath: directory.appending(path: "reinstalled").path, contents: Data("3".utf8))
                    await waitUntilRecorded("/reinstalled")
                    let recordedAfterReinstall = DiskIOStore.shared.events.map { ($0.path as NSString).lastPathComponent }
                    drawer.unregisterGlobal(id: DiskIOPlugin().id)
                    let afterLastUninstall = try implementations()

                    #expect(zip(whileInstalled, expected).allSatisfy { $0 != $1 })
                    #expect(actual == expected)
                    #expect(!drawer.globalPlugins.contains { $0.id == DiskIOPlugin().id })
                    #expect(keptAfterUninstall == 0)
                    #expect(afterSecondUninstall == expected)
                    #expect(recordedAfterReinstall.contains("reinstalled"))
                    #expect(!recordedAfterReinstall.contains("uninstalled"))
                    #expect(!recordedAfterReinstall.contains("installed"))
                    #expect(afterLastUninstall == expected)
                }
                try await uninstallThenReinstall()
            }
        }

        @Test("A method other code swapped in on top stays after the uninstall, and its calls aren't recorded until the plugin is installed again")
        func swizzleOnTopIsLeftInPlace() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func contentsImplementation() throws -> IMP {
                    try method_getImplementation(#require(class_getInstanceMethod(FileManager.self, #selector(FileManager.contents(atPath:)))))
                }

                @MainActor
                func leaveInPlace() async throws {
                    let suite = "DiskIOUninstallExitTests.\(UUID().uuidString)"
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let directory = FileManager.default.temporaryDirectory.appending(path: "DiskIOOnTop-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let left = directory.appending(path: "left").path
                    let again = directory.appending(path: "again").path
                    _ = FileManager.default.createFile(atPath: left, contents: Data("1".utf8))
                    _ = FileManager.default.createFile(atPath: again, contents: Data("2".utf8))
                    drawer.installDiskIO()
                    try method_exchangeImplementations(
                        #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.contents(atPath:)))),
                        #require(class_getInstanceMethod(FileManager.self, #selector(FileManager.onTopContents(atPath:))))
                    )
                    let expected = try contentsImplementation()

                    drawer.unregisterGlobal(id: DiskIOPlugin().id)
                    let actual = try contentsImplementation()
                    let readWhileLeftInPlace = FileManager.default.contents(atPath: left)
                    drawer.installDiskIO()
                    let readReinstalled = FileManager.default.contents(atPath: again)
                    for await events in DiskIOStore.shared.$events.values where events.contains(where: { $0.path == again }) {
                        break
                    }
                    let recorded = DiskIOStore.shared.events.map(\.path)

                    #expect(actual == expected)
                    #expect(readWhileLeftInPlace == Data("1".utf8))
                    #expect(readReinstalled == Data("2".utf8))
                    #expect(recorded.contains(again))
                    #expect(!recorded.contains(left))
                }
                try await leaveInPlace()
            }
        }
    }
#endif
