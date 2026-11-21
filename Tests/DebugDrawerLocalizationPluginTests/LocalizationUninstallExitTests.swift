// Uninstalling puts Bundle's lookups back for the whole process, so these run in a child process
// each, in a file of their own, as exit tests need one. Each writes a bundle of its own to the
// temporary folder and makes it the app's.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerLocalizationPlugin
    import Foundation
    import ObjectiveC
    import Testing

    @Suite("Localization uninstall, in a child process")
    struct LocalizationUninstallExitTests {
        @Test("Unregistering puts both lookups back and the strings show their translations; installing again intercepts")
        func restoresLookups() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                try FileManager.default.createDirectory(at: app.appending(path: "en.lproj"), withIntermediateDirectories: true)
                try Data("\"settings.title\" = \"Settings\";".utf8).write(to: app.appending(path: "en.lproj/Localizable.strings"))
                try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                    format: .xml, options: 0
                )
                .write(to: app.appending(path: "Info.plist"))
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                @MainActor func isRestored() -> Bool {
                    func implementations() -> [IMP?] {
                        let selectors = [
                            #selector(Bundle.localizedString(forKey:value:table:)),
                            NSSelectorFromString("localizedStringForKey:value:table:localizations:")
                        ]
                        return selectors
                            .map { class_getInstanceMethod(Bundle.self, $0).map(method_getImplementation) }
                    }
                    let expected = implementations()
                    guard let appBundle = Bundle(url: app) else { return false }

                    Localization.install(mode: .pseudoLocalized)
                    let installed = implementations()
                    let pseudo = NSLocalizedString("settings.title", bundle: appBundle, comment: "")
                    DebugDrawer.shared.unregisterGlobal(id: LocalizationPlugin.pluginID)
                    let uninstalled = implementations()
                    let translated = NSLocalizedString("settings.title", bundle: appBundle, comment: "")
                    let isListed = DebugDrawer.shared.globalPlugins.contains { $0.id == LocalizationPlugin.pluginID }
                    let modeUninstalled = LocalizationState.shared.mode
                    DebugDrawer.shared.unregisterGlobal(id: LocalizationPlugin.pluginID)
                    let twice = implementations()
                    Localization.install(mode: .showingKeys)
                    let reinstalled = implementations()
                    let key = NSLocalizedString("settings.title", bundle: appBundle, comment: "")

                    // The second lookup exists from macOS 15.4 on; before, it is nil throughout.
                    let isReplaced = installed[0] != expected[0] && (expected[1] == nil || installed[1] != expected[1])
                    return isReplaced && pseudo == "[Šéţţîñĝš····]" && uninstalled == expected && translated == "Settings" && !isListed
                        && modeUninstalled == .standard && twice == expected && reinstalled[0] != expected[0] && key == "settings.title"
                }
                exit(await MainActor.run { isRestored() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Unregistering drops the untranslated lookups recorded and the tables read; lookups made then aren't recorded")
        func dropsLookups() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                try FileManager.default.createDirectory(at: app.appending(path: "en.lproj"), withIntermediateDirectories: true)
                try Data("\"settings.title\" = \"Settings\";".utf8).write(to: app.appending(path: "en.lproj/Localizable.strings"))
                try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                    format: .xml, options: 0
                )
                .write(to: app.appending(path: "Info.plist"))
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                @MainActor func isDropped() async -> Bool {
                    guard let appBundle = Bundle(url: app) else { return false }
                    let model = LocalizationInstallation.install(mode: .standard, source: BundleTableSource(appBundles: AppBundles(root: root.path)))
                    _ = appBundle.localizedString(forKey: "banner.new", value: "New: faster checkout", table: nil)
                    await model.refresh()
                    let lookupsInstalled = model.lookups.count
                    let bundlesInstalled = model.bundles.count

                    DebugDrawer.shared.unregisterGlobal(id: LocalizationPlugin.pluginID)
                    let fallback = appBundle.localizedString(forKey: "banner.later", value: "Later", table: nil)

                    return lookupsInstalled == 1 && bundlesInstalled > 0 && fallback == "Later"
                        && model.lookups.isEmpty && model.bundles.isEmpty && LocalizationState.shared.lookups.isEmpty
                }
                exit(await isDropped() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Unregistered under a replacement other code made since, the lookup keeps that one, and the plugin's under it calls straight through")
        func keptUnderAnotherReplacement() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                try FileManager.default.createDirectory(at: app.appending(path: "en.lproj"), withIntermediateDirectories: true)
                try Data("\"settings.title\" = \"Settings\";".utf8).write(to: app.appending(path: "en.lproj/Localizable.strings"))
                try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                    format: .xml, options: 0
                )
                .write(to: app.appending(path: "Info.plist"))
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                @MainActor func isStraightThrough() -> Bool {
                    typealias Lookup = @convention(c) (Bundle, Selector, NSString?, NSString?, NSString?) -> NSString
                    let selector = #selector(Bundle.localizedString(forKey:value:table:))
                    guard let appBundle = Bundle(url: app), let method = class_getInstanceMethod(Bundle.self, selector) else { return false }

                    Localization.install(mode: .pseudoLocalized)
                    let plugins = unsafeBitCast(method_getImplementation(method), to: Lookup.self)
                    let other: @convention(block) (Bundle, NSString?, NSString?, NSString?) -> NSString = { bundle, key, value, table in
                        plugins(bundle, selector, key, value, table)
                    }
                    let otherIMP = imp_implementationWithBlock(other)
                    method_setImplementation(method, otherIMP)
                    DebugDrawer.shared.unregisterGlobal(id: LocalizationPlugin.pluginID)
                    // Pseudo-localized while intercepting: the mode, were it applied, would show.
                    LocalizationState.shared.mode = .pseudoLocalized
                    let translated = NSLocalizedString("settings.title", bundle: appBundle, comment: "")
                    let fallback = appBundle.localizedString(forKey: "banner.later", value: "Later", table: nil)

                    return method_getImplementation(method) == otherIMP && translated == "Settings" && fallback == "Later"
                        && LocalizationState.shared.lookups.isEmpty
                }
                exit(await MainActor.run { isStraightThrough() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A plugin in two drawers intercepts until the last removes it")
        func twoDrawers() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    let suite = "LocalizationUninstallExitTests.\(UUID().uuidString)"
                    guard let first = UserDefaults(suiteName: suite + ".first"), let second = UserDefaults(suiteName: suite + ".second") else {
                        return false
                    }
                    let selector = #selector(Bundle.localizedString(forKey:value:table:))
                    guard let method = class_getInstanceMethod(Bundle.self, selector) else { return false }
                    let expected = method_getImplementation(method)
                    let firstDrawer = DebugDrawer(defaults: first)
                    let secondDrawer = DebugDrawer(defaults: second)
                    let model = LocalizationModel(source: BundleTableSource(appBundles: .main), state: .shared)
                    let sut = LocalizationPlugin(model: model)

                    firstDrawer.registerGlobal(sut)
                    secondDrawer.registerGlobal(sut)
                    firstDrawer.unregisterGlobal(id: sut.id)
                    let inSecond = method_getImplementation(method)
                    secondDrawer.unregisterGlobal(id: sut.id)

                    return inSecond != expected && method_getImplementation(method) == expected
                        && !secondDrawer.globalPlugins.contains { $0.id == sut.id }
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
