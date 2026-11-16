#if DEBUG
    @testable import DebugDrawerLoadedLibrariesPlugin
    import Foundation
    import MachO
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite struct LoadedLibrariesPluginTests {
        // MARK: Categories

        @Test(arguments: [
            ("/var/containers/Bundle/Application/X/My.app/Frameworks/Foo.framework/Foo",
             "/var/containers/Bundle/Application/X/My.app"),
            ("/Applications/My.app/Contents/Frameworks/Foo.framework/Versions/A/Foo", "/Applications/My.app"),
            ("/opt/homebrew/lib/libfoo.dylib", "/Applications/My.app"),
            // A sibling bundle whose name starts the same isn't inside this one.
            ("/Applications/My.app2/Contents/MacOS/Other", "/Applications/My.app")
        ])
        func embeddedFrameworksAndOutsideImagesAreThirdParty(path: String, bundle: String) {
            #expect(LoadedLibrary.categorize(path: path, bundlePath: bundle) == .thirdParty)
        }

        @Test(arguments: [
            ("/var/containers/Bundle/Application/X/My.app/My", "/var/containers/Bundle/Application/X/My.app"),
            ("/Applications/My.app/Contents/MacOS/My", "/Applications/My.app"),
            ("/Applications/My.app/Contents/MacOS/My.debug.dylib", "/Applications/My.app")
        ])
        func mainExecutableAndOtherBundleImagesAreApp(path: String, bundle: String) {
            #expect(LoadedLibrary.categorize(path: path, bundlePath: bundle) == .app)
        }

        @Test(arguments: ["/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"])
        func systemImagesAreSystem(path: String) {
            #expect(LoadedLibrary.categorize(path: path, bundlePath: "/Applications/My.app") == .system)
        }

        @Test func thisProcessMainExecutableIsAppWhenItsBundleIsTheApp() throws {
            // dyld's image 0 is the main executable. Under a test runner that's the runner,
            // so treat its directory as the app bundle to check loadAll() end to end.
            let executable = String(cString: try #require(_dyld_get_image_name(0)))
            let bundle = (executable as NSString).deletingLastPathComponent
            let main = try #require(LoadedLibrary.loadAll(bundlePath: bundle).first { $0.path == executable })
            #expect(main.category == .app)
        }

        // MARK: UUID and load address

        // dwarfdump is the independent reference, and only the Mac can start it.
        #if os(macOS)
        @Test func eachImageHasItsLoadAddressAndUUID() throws {
            // The image holding this test: dladdr gives its path and header address independently of dyld's list.
            var info = Dl_info()
            #expect(dladdr(#dsohandle, &info) != 0)
            let path = String(cString: try #require(info.dli_fname))
            let base = UInt(bitPattern: info.dli_fbase)

            let libraries = LoadedLibrary.loadAll()
            let image = try #require(libraries.first { $0.path == path }, "\(path) not listed")
            #expect(image.loadAddress == base)
            #expect(image.loadAddressLabel == String(format: "0x%llx", UInt64(base)))

            let uuid = try #require(image.uuid)
            let expected = try #require(dwarfdumpUUIDs(path), "dwarfdump couldn't read \(path)")
            #expect(expected.contains(uuid), "\(uuid) not in dwarfdump's \(expected)")

            #expect(libraries.allSatisfy { $0.uuid != nil }, "every loaded Mach-O image has an LC_UUID")
            #expect(Set(libraries.map(\.loadAddress)).count == libraries.count, "load addresses are distinct")
        }

        /// The UUIDs `dwarfdump --uuid` reports for a Mach-O file, or nil where dwarfdump can't run.
        private func dwarfdumpUUIDs(_ path: String) -> Set<UUID>? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["dwarfdump", "--uuid", path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do { try process.run() } catch { return nil }
            guard let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return nil }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            // "UUID: 1234ABCD-... (arm64) /path"
            return Set(output.split(separator: "\n").compactMap { line in
                line.split(separator: " ").dropFirst().first.flatMap { UUID(uuidString: String($0)) }
            })
        }

        #endif

        @Test func rowShowsUUIDLoadAddressAndVersion() throws {
            let uuid = UUID()
            let library = LoadedLibrary(id: 1, name: "Foo", path: "/x/Foo.framework/Foo", category: .thirdParty,
                                        uuid: uuid, loadAddress: 0x1_0400_0000, version: "2.3.1")
            let texts = try LoadedLibraryRow(library: library).inspect().findAll(ViewType.Text.self).map { try $0.string() }
            #expect(texts.contains("\(uuid.uuidString) · 0x104000000"), "\(texts)")
            #expect(texts.contains("2.3.1"), "\(texts)")
        }
    }
#endif
