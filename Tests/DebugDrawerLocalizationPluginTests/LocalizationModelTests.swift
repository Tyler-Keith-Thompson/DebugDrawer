#if DEBUG
    @testable import DebugDrawerLocalizationPlugin
    import Foundation
    import Testing

    /// Bundles given by the test, in place of the app's.
    private struct FixedTableSource: LocalizationTableSource {
        let fixed: [LocalizedBundle]

        func bundles() -> [LocalizedBundle] {
            fixed
        }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocalizationModelTests {
        @Test("Setting the mode sets the interception's and reports the change once; setting it again reports nothing")
        func mode() {
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            var changes = 0
            let sut = LocalizationModel(source: FixedTableSource(fixed: []), state: state) { changes += 1 }

            sut.mode = .pseudoLocalized
            sut.mode = .pseudoLocalized

            #expect(state.mode == .pseudoLocalized)
            #expect(state.mode(forBundleAt: "/App.app/Kit.framework") == .pseudoLocalized)
            #expect(state.mode(forBundleAt: "/System/Library/Frameworks/UIKit.framework") == nil)
            #expect(changes == 1)
        }

        @Test("The model starts in the interception's mode")
        func initialMode() {
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            state.mode = .showingKeys

            let sut = LocalizationModel(source: FixedTableSource(fixed: []), state: state)

            #expect(sut.mode == .showingKeys)
        }

        @Test("Refresh reads the bundles; the current language's missing translations come from them and the lookups")
        func refresh() async {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A"), "b": LocalizationEntry("B")])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("Ä")])]
                ]
            )
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            state.record(LocalizationLookup(bundlePath: "/App.app", table: nil, key: "c", defaultValue: "C"))
            let sut = LocalizationModel(source: FixedTableSource(fixed: [bundle]), state: state)
            let expected = [
                MissingTranslation(group: "Localizable", key: "b", developmentValue: "B", isLookedUp: false),
                MissingTranslation(group: "Localizable", key: "c", developmentValue: "C", isLookedUp: true)
            ]

            await sut.refresh()

            #expect(sut.bundles == [bundle])
            #expect(sut.currentMissing == expected)
        }

        @Test("A lookup recorded off the main actor reaches the model")
        func lookupArrives() async {
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            let sut = LocalizationModel(source: FixedTableSource(fixed: []), state: state)
            let updates = sut.$lookups.values
            let expected = [LocalizationLookup(bundlePath: "/App.app", table: "Errors", key: "error.unknown", defaultValue: nil)]

            await Task.detached {
                state.record(LocalizationLookup(bundlePath: "/App.app", table: "Errors", key: "error.unknown", defaultValue: nil))
            }.value
            var actual: [LocalizationLookup] = []
            for await lookups in updates where !lookups.isEmpty {
                actual = lookups
                break
            }

            #expect(actual == expected)
        }

        @Test("A lookup is kept once, however often it repeats, and the list stops at its capacity")
        func lookupCapacity() {
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            let repeated = LocalizationLookup(bundlePath: "/App.app", table: nil, key: "same", defaultValue: nil)

            for _ in 0 ..< 3 {
                state.record(repeated)
            }
            for index in 0 ..< LocalizationState.lookupCapacity + 5 {
                state.record(LocalizationLookup(bundlePath: "/App.app", table: nil, key: "key \(index)", defaultValue: nil))
            }
            let actual = state.lookups

            #expect(actual.count == LocalizationState.lookupCapacity)
            #expect(actual.first == repeated)
            #expect(actual.last?.key == "key \(LocalizationState.lookupCapacity - 2)")
        }

        @Test("With no bundles there is no current language and nothing missing")
        func noBundles() async {
            let sut = LocalizationModel(
                source: FixedTableSource(fixed: []), state: LocalizationState(appBundles: AppBundles(root: "/App.app"))
            )

            await sut.refresh()

            #expect(sut.bundles.currentLocalization == nil)
            #expect(sut.currentMissing.isEmpty)
        }

        @Test("The rewrite keeps the result as it is, shows the key, or pseudo-localizes")
        func rewrite() {
            let standard = LocalizationInterception.rewrite("Settings", key: "settings.title", mode: .standard)
            let keys = LocalizationInterception.rewrite("Settings", key: "settings.title", mode: .showingKeys)
            let emptyKey = LocalizationInterception.rewrite("Settings", key: "", mode: .showingKeys)
            let pseudo = LocalizationInterception.rewrite("Settings", key: "settings.title", mode: .pseudoLocalized)

            #expect(standard == "Settings")
            #expect(keys == "settings.title")
            #expect(emptyKey == "Settings")
            #expect(pseudo == "[Šéţţîñĝš····]")
        }
    }
#endif
