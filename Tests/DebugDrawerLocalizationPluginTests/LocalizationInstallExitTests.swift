// Installing replaces Bundle's lookups for the whole process and registers the plugin with its
// drawer, so these run in a child process each, in a file of their own, as exit tests need one.
// Each writes a bundle of its own to the temporary folder and makes it the app's. The README's
// example is here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerLocalizationPlugin
    import Foundation
    import Testing

    @Suite("Localization install, in a child process")
    struct LocalizationInstallExitTests {
        @Test("Pseudo-localized, the app's strings are accented, longer and bracketed; another bundle's are untouched")
        func pseudoLocalized() async {
            await #expect(processExitsWith: .success) {
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                let outside = FileManager.default.temporaryDirectory.appending(path: "LocalizationExit-\(UUID().uuidString)/Other.bundle")
                for bundle in [app, outside] {
                    try FileManager.default.createDirectory(at: bundle.appending(path: "en.lproj"), withIntermediateDirectories: true)
                    try Data("\"settings.title\" = \"Settings\";\n\"delivery\" = \"Delivery: %@\";".utf8)
                        .write(to: bundle.appending(path: "en.lproj/Localizable.strings"))
                    try PropertyListSerialization.data(
                        fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                        format: .xml, options: 0
                    )
                    .write(to: bundle.appending(path: "Info.plist"))
                }
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                let isExpected = await MainActor.run {
                    Localization.install(mode: .pseudoLocalized)
                    let appBundle = Bundle(url: app)!
                    let otherBundle = Bundle(url: outside)!
                    return NSLocalizedString("settings.title", bundle: appBundle, comment: "") == "[Šéţţîñĝš····]"
                        && String(format: NSLocalizedString("delivery", bundle: appBundle, comment: ""), "Friday") == "[Ðéļîṽéŕý: Friday····]"
                        && appBundle.localizedString(forKey: "unknown.key", value: "Fallback", table: nil) == "[Ƒáļļƀáçķ····]"
                        && NSLocalizedString("settings.title", bundle: otherBundle, comment: "") == "Settings"
                        // In no table and with no default value: SwiftUI's own text, an alert title, say.
                        && appBundle.localizedString(forKey: "Delete File", value: nil, table: nil) == "Delete File"
                        && LocalizationState.shared.lookups.map(\.key) == ["unknown.key"]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Pseudo-localized, a plural keeps its rules: each count formats with its own variant")
        func pseudoLocalizedPlural() async {
            await #expect(processExitsWith: .success) {
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                try FileManager.default.createDirectory(at: app.appending(path: "en.lproj"), withIntermediateDirectories: true)
                let plural: [String: Any] = [
                    "orders.count": [
                        "NSStringLocalizedFormatKey": "%#@orders@ waiting",
                        "orders": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld",
                                   "one": "%lld order", "other": "%lld orders"]
                    ]
                ]
                try PropertyListSerialization.data(fromPropertyList: plural, format: .xml, options: 0)
                    .write(to: app.appending(path: "en.lproj/Localizable.stringsdict"))
                try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                    format: .xml, options: 0
                )
                .write(to: app.appending(path: "Info.plist"))
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                let isExpected = await MainActor.run {
                    let appBundle = Bundle(url: app)!
                    let standardOne = String.localizedStringWithFormat(NSLocalizedString("orders.count", bundle: appBundle, comment: ""), 1)
                    Localization.install(mode: .pseudoLocalized)
                    let one = String.localizedStringWithFormat(NSLocalizedString("orders.count", bundle: appBundle, comment: ""), 1)
                    let three = String.localizedStringWithFormat(NSLocalizedString("orders.count", bundle: appBundle, comment: ""), 3)
                    return standardOne == "1 order waiting" && one == "[1 öŕðéŕ ŵáîţîñĝ····]" && three == "[3 öŕðéŕš ŵáîţîñĝ····]"
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Showing keys, each of the app's strings is its key, a plural's too; turned off, the translations are back")
        func showingKeys() async {
            await #expect(processExitsWith: .success) {
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                try FileManager.default.createDirectory(at: app.appending(path: "en.lproj"), withIntermediateDirectories: true)
                try Data("\"settings.title\" = \"Settings\";".utf8).write(to: app.appending(path: "en.lproj/Localizable.strings"))
                let plural: [String: Any] = [
                    "orders.count": [
                        "NSStringLocalizedFormatKey": "%#@orders@",
                        "orders": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld",
                                   "one": "%lld order", "other": "%lld orders"]
                    ]
                ]
                try PropertyListSerialization.data(fromPropertyList: plural, format: .xml, options: 0)
                    .write(to: app.appending(path: "en.lproj/Localizable.stringsdict"))
                try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                    format: .xml, options: 0
                )
                .write(to: app.appending(path: "Info.plist"))
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                let isExpected = await MainActor.run {
                    let model = LocalizationInstallation.install(mode: .showingKeys)
                    let appBundle = Bundle(url: app)!
                    let key = NSLocalizedString("settings.title", bundle: appBundle, comment: "")
                    let pluralKey = String.localizedStringWithFormat(NSLocalizedString("orders.count", bundle: appBundle, comment: ""), 2)
                    let generation = LocalizationRedraw.shared.generation
                    model.mode = .standard
                    let translated = NSLocalizedString("settings.title", bundle: appBundle, comment: "")
                    return key == "settings.title" && pluralKey == "orders.count" && translated == "Settings"
                        && LocalizationRedraw.shared.generation == generation + 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("An untranslated lookup in an app bundle is recorded once and listed as missing; one in another bundle isn't")
        func recordsLookups() async {
            await #expect(processExitsWith: .success) {
                let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "LocalizationExit-\(UUID().uuidString)")
                let app = root.appending(path: "App.bundle")
                for (localization, strings) in [("en", "\"settings.title\" = \"Settings\";"), ("de", "\"settings.title\" = \"Einstellungen\";")] {
                    try FileManager.default.createDirectory(at: app.appending(path: "\(localization).lproj"), withIntermediateDirectories: true)
                    try Data(strings.utf8).write(to: app.appending(path: "\(localization).lproj/Localizable.strings"))
                }
                try PropertyListSerialization.data(
                    fromPropertyList: ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"],
                    format: .xml, options: 0
                )
                .write(to: app.appending(path: "Info.plist"))
                LocalizationState.shared.appBundles = AppBundles(root: root.path)
                @MainActor
                func isExpected() async -> Bool {
                    let model = LocalizationInstallation.install(mode: .standard, source: BundleTableSource(appBundles: AppBundles(root: root.path)))
                    let updates = model.$lookups.values
                    let appBundle = Bundle(url: app)!
                    let fallback = appBundle.localizedString(forKey: "banner.new", value: "New: faster checkout", table: nil)
                    _ = appBundle.localizedString(forKey: "banner.new", value: "New: faster checkout", table: nil)
                    _ = Bundle.main.localizedString(forKey: "outside.key", value: nil, table: "Elsewhere")
                    _ = NSLocalizedString("settings.title", bundle: appBundle, comment: "")
                    await model.refresh()
                    for await lookups in updates where !lookups.isEmpty {
                        let path = app.standardizedFileURL.path
                        let missing = MissingTranslation.find(in: model.bundles, localization: "de", lookups: lookups)
                        return fallback == "New: faster checkout"
                            && lookups == [LocalizationLookup(bundlePath: path, table: nil, key: "banner.new", defaultValue: "New: faster checkout")]
                            && missing == [
                                MissingTranslation(
                                    group: "App.bundle · Localizable", key: "banner.new", developmentValue: "New: faster checkout", isLookedUp: true
                                )
                            ]
                    }
                    return false
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once and sets the mode")
        func installAgain() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    Localization.install(mode: .pseudoLocalized)
                    Localization.install(mode: .showingKeys)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Localization" }
                    return plugins == 1 && LocalizationState.shared.mode == .showingKeys
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Localization")
        func readme() async {
            await #expect(processExitsWith: .success) {
                let isInstalled = await MainActor.run {
                    // At startup, before the first string is looked up:
                    Localization.install()

                    // Or, for a launch argument of the app's own, starting pseudo-localized:
                    Localization.install(mode: ProcessInfo.processInfo.arguments.contains("-PseudoLocalize") ? .pseudoLocalized : .standard)

                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "Localization" }
                        && LocalizationState.shared.mode == .standard
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
