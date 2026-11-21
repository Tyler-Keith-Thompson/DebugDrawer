#if DEBUG
    @testable import DebugDrawerLocalizationPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    // Each test stores into a defaults suite of its own, named for it, in place of the app's
    // domain, and removes the suite when it ends.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NextLaunchTests {
        /// Bundles given by the test: none.
        private struct NoTables: LocalizationTableSource {
            func bundles() -> [LocalizedBundle] {
                []
            }
        }

        @Test("Pseudo-localizing stores Foundation's accent and double keys as true; turning it off removes them")
        func storesPseudoKeys() throws {
            let name = temporarySuiteName("NextLaunchTests")
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = NextLaunchDefaults(defaults: defaults, domainName: name)
            let expectedOn: [String: Bool] = ["NSAccentuateLocalizedStrings": true, "NSDoubleLocalizedStrings": true]

            sut.set(.pseudoLocalized, isOn: true)
            let on = defaults.persistentDomain(forName: name) as? [String: Bool]
            let storedOn = sut.stored()
            sut.set(.pseudoLocalized, isOn: false)
            let off = defaults.persistentDomain(forName: name) ?? [:]

            #expect(on == expectedOn)
            #expect(storedOn == [.pseudoLocalized])
            #expect(off.isEmpty)
            #expect(sut.stored().isEmpty)
        }

        @Test("Untranslated in Capitals stores NSShowNonLocalizedStrings alone")
        func storesShowNonLocalized() throws {
            let name = temporarySuiteName("NextLaunchTests")
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let sut = NextLaunchDefaults(defaults: defaults, domainName: name)
            let expected: [String: Bool] = ["NSShowNonLocalizedStrings": true]

            sut.set(.untranslatedInCapitals, isOn: true)

            #expect(defaults.persistentDomain(forName: name) as? [String: Bool] == expected)
            #expect(sut.stored() == [.untranslatedInCapitals])
        }

        @Test("An option counts as stored only when every key is true: one key, or false, isn't")
        func partialKeysArentStored() throws {
            let name = temporarySuiteName("NextLaunchTests")
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(true, forKey: "NSAccentuateLocalizedStrings")
            defaults.set(false, forKey: "NSShowNonLocalizedStrings")
            let sut = NextLaunchDefaults(defaults: defaults, domainName: name)

            let actual = sut.stored()

            #expect(actual.isEmpty)
        }

        @Test("The model starts with what is stored as launched; a change makes a relaunch pending, and undoing it doesn't")
        func relaunchPending() throws {
            let name = temporarySuiteName("NextLaunchTests")
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            NextLaunchDefaults(defaults: defaults, domainName: name).set(.untranslatedInCapitals, isOn: true)
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            let sut = LocalizationModel(
                source: NoTables(), state: state, nextLaunchDefaults: NextLaunchDefaults(defaults: defaults, domainName: name)
            )
            let launchedWith = sut.launchedWith
            let pendingAtLaunch = sut.isRelaunchPending

            sut.setNextLaunch(.pseudoLocalized, isOn: true)
            let afterOn = (sut.nextLaunch, sut.isRelaunchPending)
            sut.setNextLaunch(.pseudoLocalized, isOn: false)

            #expect(launchedWith == [.untranslatedInCapitals])
            #expect(!pendingAtLaunch)
            #expect(afterOn.0 == [.untranslatedInCapitals, .pseudoLocalized])
            #expect(afterOn.1)
            #expect(sut.nextLaunch == [.untranslatedInCapitals])
            #expect(!sut.isRelaunchPending)
        }

        @Test("With no defaults to store in, the model stores nothing and nothing is pending")
        func noDefaults() {
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            let sut = LocalizationModel(source: NoTables(), state: state)

            sut.setNextLaunch(.pseudoLocalized, isOn: true)

            #expect(sut.nextLaunch.isEmpty)
            #expect(!sut.isRelaunchPending)
        }

        @Test("The summary lists the options in the plugin's order")
        func summary() {
            let options: Set<NextLaunchOption> = [.untranslatedInCapitals, .pseudoLocalized]

            let actual = options.summary

            #expect(actual == "Accented and Doubled, Untranslated in Capitals")
        }
    }
#endif
