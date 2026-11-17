#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerLocalizationPlugin
    import Foundation
    import Testing

    /// No bundles, in place of the app's.
    private struct EmptyTableSource: LocalizationTableSource {
        func bundles() -> [LocalizedBundle] {
            []
        }
    }

    @MainActor
    @Suite
    struct LocalizationPluginTests {
        @Test("The plugin is Localization, in Interface, with a header accessory, and adds to bug reports")
        func identity() {
            let model = LocalizationModel(source: EmptyTableSource(), state: LocalizationState(appBundles: AppBundles(root: "/App.app")))
            let sut = LocalizationPlugin(model: model)

            #expect(sut.id == "LocalizationPlugin")
            #expect(sut.title == "Localization")
            #expect(sut.category == "Interface")
            #expect(sut.icon == "character.bubble")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
            #expect(AnyDebugDrawerPlugin(sut).headerAccessory != nil)
        }

        @Test("The drawer's search toggles each mode and goes back to the translations, found by \"pseudo\" and \"keys\"")
        func actions() throws {
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            let model = LocalizationModel(source: EmptyTableSource(), state: state)
            let sut = LocalizationPlugin(model: model)
            let pseudo = try #require(sut.actions.first { $0.keywords.contains("pseudo") })
            let keys = try #require(sut.actions.first { $0.title == "Show localization keys" })
            let translations = try #require(sut.actions.first { $0.title == "Show translations" })

            pseudo.perform()
            let afterPseudo = state.mode
            keys.perform()
            let afterKeys = state.mode
            keys.perform()
            let afterKeysAgain = state.mode
            pseudo.perform()
            translations.perform()

            #expect(sut.actions.map(\.title) == ["Pseudo-localize strings", "Show localization keys", "Show translations"])
            #expect(afterPseudo == .pseudoLocalized)
            #expect(afterKeys == .showingKeys)
            #expect(afterKeysAgain == .standard)
            #expect(state.mode == .standard)
        }

        @Test("The bug report gets localization.txt: the mode, the languages and what the current one is missing")
        func report() throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A"), "b": LocalizationEntry("B")])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("Ä")])]
                ]
            )
            let expected = """
            Mode: pseudo-localized
            Whole app, from the app's defaults: Accented and Doubled
            Current language: de
            Development language: en
            Languages: de, en
            Missing in de (2):
            Localizable
              b = "B"
              banner = "New" (looked up)
            """
            var actual = DebugDrawerReport()

            LocalizationPlugin.contribute(
                mode: .pseudoLocalized, launchedWith: [.pseudoLocalized], bundles: [bundle],
                lookups: [LocalizationLookup(bundlePath: "/App.app", table: nil, key: "banner", defaultValue: "New")], to: &actual
            )

            let file = try #require(actual.files.first)
            #expect(actual.files.map(\.name) == ["localization.txt"])
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("With no tables the report says so")
        func reportEmpty() {
            let expected = """
            Mode: translations
            Whole app, from the app's defaults: off
            Current language: unknown
            Development language: unknown
            Languages: none
            """

            let actual = LocalizationPlugin.text(mode: .standard, launchedWith: [], bundles: [], lookups: [])

            #expect(actual == expected)
        }

        @Test("A complete translation reports nothing missing")
        func reportComplete() {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "en",
                tables: ["en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])]]
            )

            let expected = """
            Mode: showing keys
            Whole app, from the app's defaults: Accented and Doubled, Untranslated in Capitals
            Current language: en
            Development language: en
            Languages: en
            Missing in en: none
            """

            let actual = LocalizationPlugin.text(
                mode: .showingKeys, launchedWith: [.untranslatedInCapitals, .pseudoLocalized], bundles: [bundle], lookups: []
            )

            #expect(actual == expected)
        }

        @Test("Launch arguments are Apple's, with -AppleLanguages for the language given")
        func launchArguments() {
            let expected = [
                "-NSDoubleLocalizedStrings YES", "-NSAccentuateLocalizedStrings YES", "-NSShowNonLocalizedStrings YES",
                "-NSForceRightToLeftWritingDirection YES", "-AppleLanguages (de)"
            ]

            let actual = LaunchArgument.all(language: "de").map(\.argument)
            let withoutLanguage = LaunchArgument.all(language: nil).map(\.argument)

            #expect(actual == expected)
            #expect(withoutLanguage == Array(expected.dropLast()))
        }
    }
#endif
