#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerLoadedLibrariesPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. dyld's list
    // is a hand-written fake; nothing reads the process's own images. Every command lands before
    // `send(_:)` returns, so no test waits.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LoadedLibrariesModelTests {
        @Test("A snapshot of the libraries read, with a filter and a category, encodes to JSON and decodes equal")
        func snapshotRoundTrips() throws {
            let images = FakeLoadedImageList()
            images.load("/Applications/My.app/Contents/MacOS/My", uuid: UUID(uuidString: "6F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9"))
            images.load(
                "/Applications/My.app/Contents/Frameworks/Charts.framework/Versions/A/Charts",
                uuid: UUID(uuidString: "0A1B2C3D-4E5F-4061-8293-A4B5C6D7E8F9"), frameworkVersion: "5.1.0"
            )
            images.load("/usr/lib/libSystem.B.dylib")
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            sut.send(LoadedLibrariesCommand(.refresh))
            sut.send(LoadedLibrariesCommand(.setFilter("charts")))
            sut.send(LoadedLibrariesCommand(.setCategory(.thirdParty)))
            let expected = sut.snapshot

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(LoadedLibrariesSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.libraries.count == 3)
            #expect(actual.filter == "charts")
            #expect(actual.category == .thirdParty)
            #expect(actual.shownLibraries.map(\.name) == ["Charts"])
            #expect(actual.shownLibraries.first?.version == "5.1.0")
        }

        @Test("A snapshot before the images are read encodes to JSON and decodes equal, with no libraries")
        func unreadSnapshotRoundTrips() throws {
            let images = FakeLoadedImageList(["/usr/lib/libSystem.B.dylib"])
            let sut = LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app")
            let expected = LoadedLibrariesSnapshot(libraries: [], filter: "", category: nil)

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(LoadedLibrariesSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(images.reads == 0)
        }

        @Test("Every command, encoded to JSON and decoded, drives the model through a direct transport")
        func commandsRoundTrip() throws {
            let images = FakeLoadedImageList([
                "/Applications/My.app/Contents/MacOS/My",
                "/opt/homebrew/lib/libfoo.dylib",
                "/usr/lib/libSystem.B.dylib"
            ])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            let commands = [
                LoadedLibrariesCommand(.refresh),
                LoadedLibrariesCommand(.setFilter("lib")),
                LoadedLibrariesCommand(.setCategory(.system))
            ]
            let expectedShown = ["libSystem.B.dylib"]

            for command in commands {
                try sut.send(JSONDecoder().decode(LoadedLibrariesCommand.self, from: JSONEncoder().encode(command)))
            }

            #expect(images.reads == 1)
            #expect(sut.snapshot.libraries.count == 3)
            #expect(sut.snapshot.filter == "lib")
            #expect(sut.snapshot.category == .system)
            #expect(sut.snapshot.shownLibraries.map(\.name) == expectedShown)
        }

        @Test("Picking All after a category, encoded to JSON and decoded, shows every category again")
        func allCategoriesRoundTrips() throws {
            let images = FakeLoadedImageList(["/Applications/My.app/Contents/MacOS/My", "/usr/lib/libSystem.B.dylib"])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            sut.send(LoadedLibrariesCommand(.refresh))
            sut.send(LoadedLibrariesCommand(.setCategory(.app)))
            let all = try JSONEncoder().encode(LoadedLibrariesCommand(.setCategory(nil)))

            try sut.send(JSONDecoder().decode(LoadedLibrariesCommand.self, from: all))

            #expect(sut.snapshot.category == nil)
            #expect(sut.snapshot.shownLibraries.count == 2)
        }

        @Test("Refresh puts the app's executable and bundle under App, embedded and outside images under Third-Party, and the OS's under System")
        func categorizes() {
            let images = FakeLoadedImageList([
                "/Applications/My.app/Contents/MacOS/My",
                "/Applications/My.app/Contents/MacOS/My.debug.dylib",
                "/Applications/My.app/Contents/Frameworks/Charts.framework/Versions/A/Charts",
                "/opt/homebrew/lib/libfoo.dylib",
                "/Applications/My.app2/Contents/MacOS/Other",
                "/usr/lib/libSystem.B.dylib",
                "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
            ])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            let expected: [String: LibraryCategory] = [
                "My": .app,
                "My.debug.dylib": .app,
                "Charts": .thirdParty,
                "libfoo.dylib": .thirdParty,
                "Other": .thirdParty,
                "libSystem.B.dylib": .system,
                "SwiftUI": .system
            ]

            sut.send(LoadedLibrariesCommand(.refresh))
            let actual = Dictionary(uniqueKeysWithValues: sut.snapshot.libraries.map { ($0.name, $0.category) })

            #expect(actual == expected)
        }

        @Test("Each library keeps its image's dyld index, path, UUID, load address and framework version, and is named by its file")
        func keepsWhatDyldSays() {
            let uuid = UUID()
            let images = FakeLoadedImageList(["/usr/lib/libSystem.B.dylib"])
            images.load("/Applications/My.app/Contents/Frameworks/Charts.framework/Versions/A/Charts", uuid: uuid, frameworkVersion: "5.1.0")
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            let expected = LoadedLibrary(
                id: 1, name: "Charts", path: "/Applications/My.app/Contents/Frameworks/Charts.framework/Versions/A/Charts",
                category: .thirdParty, uuid: uuid, loadAddress: 0x1_0000_8000, version: "5.1.0"
            )

            sut.send(LoadedLibrariesCommand(.refresh))
            let actual = sut.snapshot.libraries.first { $0.name == "Charts" }

            #expect(actual == expected)
        }

        @Test("Refresh sorts the libraries by name, ignoring case, whatever order dyld loaded them in")
        func sortsByName() {
            let images = FakeLoadedImageList([
                "/usr/lib/libz.1.dylib",
                "/System/Library/Frameworks/Foundation.framework/Foundation",
                "/usr/lib/libSystem.B.dylib",
                "/Applications/My.app/Contents/MacOS/app",
                "/System/Library/Frameworks/AppKit.framework/AppKit"
            ])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            let expected = ["app", "AppKit", "Foundation", "libSystem.B.dylib", "libz.1.dylib"]

            sut.send(LoadedLibrariesCommand(.refresh))
            let actual = sut.snapshot.libraries.map(\.name)

            #expect(actual == expected)
        }

        @Test("The filter shows libraries whose name or path contains it, ignoring case")
        func filtersByNameOrPath() {
            let images = FakeLoadedImageList([
                "/opt/homebrew/lib/libfoo.dylib",
                "/opt/homebrew/Cellar/bar/libbar.dylib",
                "/usr/lib/libSystem.B.dylib"
            ])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            sut.send(LoadedLibrariesCommand(.refresh))
            let expected = ["libbar.dylib", "libfoo.dylib"]

            sut.send(LoadedLibrariesCommand(.setFilter("HOMEBREW")))
            let byPath = sut.snapshot.shownLibraries.map(\.name)
            sut.send(LoadedLibrariesCommand(.setFilter("SYSTEM.b")))
            let byName = sut.snapshot.shownLibraries.map(\.name)
            sut.send(LoadedLibrariesCommand(.setFilter("")))
            let unfiltered = sut.snapshot.shownLibraries.count

            #expect(byPath == expected)
            #expect(byName == ["libSystem.B.dylib"])
            #expect(unfiltered == 3)
            #expect(sut.snapshot.libraries.count == 3)
        }

        @Test("The category and the filter together show only the libraries that pass both")
        func filtersByCategoryAndText() {
            let images = FakeLoadedImageList([
                "/Applications/My.app/Contents/MacOS/My",
                "/Applications/My.app/Contents/Frameworks/MyKit.framework/MyKit",
                "/usr/lib/libSystem.B.dylib"
            ])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            sut.send(LoadedLibrariesCommand(.refresh))

            sut.send(LoadedLibrariesCommand(.setFilter("my")))
            sut.send(LoadedLibrariesCommand(.setCategory(.thirdParty)))
            let actual = sut.snapshot.shownLibraries.map(\.name)

            #expect(actual == ["MyKit"])
        }

        @Test("Commands land in the order sent: the last filter and category sent are the ones shown")
        func commandsInOrder() {
            let images = FakeLoadedImageList(["/usr/lib/libSystem.B.dylib", "/opt/homebrew/lib/libfoo.dylib"])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            let typed = ["l", "li", "lib", "libf"]

            sut.send(LoadedLibrariesCommand(.refresh))
            for filter in typed {
                sut.send(LoadedLibrariesCommand(.setFilter(filter)))
            }
            sut.send(LoadedLibrariesCommand(.setCategory(.system)))
            sut.send(LoadedLibrariesCommand(.setCategory(.thirdParty)))

            #expect(sut.snapshot.filter == "libf")
            #expect(sut.snapshot.category == .thirdParty)
            #expect(sut.snapshot.shownLibraries.map(\.name) == ["libfoo.dylib"])
        }

        @Test("Refresh reads dyld's list again, so an image loaded since is listed, in its place by name")
        func refreshPicksUpNewImage() {
            let images = FakeLoadedImageList(["/usr/lib/libSystem.B.dylib", "/usr/lib/libz.1.dylib"])
            let sut = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app"))
            sut.send(LoadedLibrariesCommand(.refresh))
            let before = sut.snapshot.libraries.map(\.name)
            images.load("/opt/homebrew/lib/libfoo.dylib")
            let expected = ["libfoo.dylib", "libSystem.B.dylib", "libz.1.dylib"]

            sut.send(LoadedLibrariesCommand(.refresh))
            let actual = sut.snapshot.libraries.map(\.name)

            #expect(before == ["libSystem.B.dylib", "libz.1.dylib"])
            #expect(actual == expected)
            #expect(images.reads == 2)
        }

        @Test("Installing reads nothing; leaving one of two drawers keeps the libraries, leaving the last drops them but not the filter")
        func installCounting() throws {
            let firstSuite = "LoadedLibrariesModelTests.first.\(UUID().uuidString)"
            let secondSuite = "LoadedLibrariesModelTests.second.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            defer {
                firstDefaults.removePersistentDomain(forName: firstSuite)
                secondDefaults.removePersistentDomain(forName: secondSuite)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let images = FakeLoadedImageList(["/usr/lib/libSystem.B.dylib"])
            let model = LoadedLibrariesModel(images: images, bundlePath: "/Applications/My.app")
            let sut = DebugDrawerLoadedLibrariesPlugin.LoadedLibrariesPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            let readsOnInstall = images.reads
            model.perform(LoadedLibrariesCommand(.refresh))
            model.perform(LoadedLibrariesCommand(.setFilter("lib")))
            model.perform(LoadedLibrariesCommand(.setCategory(.system)))

            first.unregisterGlobal(id: sut.id)
            let keptWhileOneHolds = model.snapshot.libraries.count
            second.unregisterGlobal(id: sut.id)
            let keptOnceNoneHolds = model.snapshot.libraries.count
            second.registerGlobal(sut)
            model.perform(LoadedLibrariesCommand(.refresh))

            #expect(readsOnInstall == 0)
            #expect(keptWhileOneHolds == 1)
            #expect(keptOnceNoneHolds == 0)
            #expect(model.snapshot.filter == "lib")
            #expect(model.snapshot.category == .system)
            #expect(model.snapshot.libraries.count == 1)
            #expect(images.reads == 2)
        }

        @Test("Uninstalling from a drawer that never installed the plugin drops nothing")
        func uninstallFromAnotherDrawer() throws {
            let suite = "LoadedLibrariesModelTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let holder = DebugDrawer(defaults: defaults)
            let stranger = DebugDrawer(defaults: defaults)
            let model = LoadedLibrariesModel(images: FakeLoadedImageList(["/usr/lib/libSystem.B.dylib"]), bundlePath: "/Applications/My.app")
            let sut = DebugDrawerLoadedLibrariesPlugin.LoadedLibrariesPlugin(model: model)
            holder.registerGlobal(sut)
            model.perform(LoadedLibrariesCommand(.refresh))

            sut.uninstall(from: stranger)

            #expect(model.snapshot.libraries.count == 1)
        }
    }
#endif
