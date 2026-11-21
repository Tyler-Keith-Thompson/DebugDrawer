// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerLocalizationPlugin
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocalizationViewTests {
        @Test("Turning Pseudo-Localize on picks that mode and shows a sample; turning Show Keys on replaces it")
        func modes() throws {
            var mode = Localization.Mode.standard
            let binding = Binding(get: { mode }, set: { mode = $0 })
            let sut = LocalizationView(mode: binding, bundles: [], lookups: [], onRefresh: {})

            try sut.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Pseudo-Localize" }).tap()
            let afterPseudo = mode
            let sample = try LocalizationView(mode: binding, bundles: [], lookups: [], onRefresh: {}).inspect().find(text: "[Šéţţîñĝš····]").string()
            try LocalizationView(mode: binding, bundles: [], lookups: [], onRefresh: {}).inspect()
                .find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Show Keys" }).tap()
            let afterKeys = mode
            try LocalizationView(mode: binding, bundles: [], lookups: [], onRefresh: {}).inspect()
                .find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Show Keys" }).tap()

            #expect(afterPseudo == .pseudoLocalized)
            #expect(sample == "[Šéţţîñĝš····]")
            #expect(afterKeys == .showingKeys)
            #expect(mode == .standard)
            #expect(throws: (any Error).self) {
                try LocalizationView(mode: binding, bundles: [], lookups: [], onRefresh: {}).inspect().find(text: "[Šéţţîñĝš····]")
            }
        }

        @Test("The current language's missing translations are listed under their tables, each key with its development text, and counted")
        func missingList() throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [
                        LocalizationTable(name: "Localizable", entries: [
                        "privacy": LocalizationEntry("Privacy Policy"),
                        "a": LocalizationEntry("A")]),
                        LocalizationTable(name: "Checkout", entries: ["promo": LocalizationEntry("Have a promo code?")])
                    ],
                    "de": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("Ä")])]
                ]
            )
            let lookups = [LocalizationLookup(bundlePath: "/App.app", table: nil, key: "banner.new", defaultValue: nil)]
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: lookups, onRefresh: {})
            let expectedKeys = ["promo", "banner.new", "privacy"]
            let expectedNote = "3 strings have no de translation. Looked up: the app asked for the key while running and got none."

            let keys = try sut.inspect().findAll(MissingTranslationRow.self).map { try $0.actualView().item.key }
            let groups = try ["Checkout", "Localizable"].map { try sut.inspect().find(text: $0).string() }
            let developmentText = try sut.inspect().find(text: "Privacy Policy").string()
            let noTable = try sut.inspect().find(text: "No table has this key").string()
            let lookedUp = try sut.inspect().find(text: "Looked up").string()
            let note = try sut.inspect().find(text: expectedNote).string()

            #expect(keys == expectedKeys)
            #expect(groups == ["Checkout", "Localizable"])
            #expect(developmentText == "Privacy Policy")
            #expect(noTable == "No table has this key")
            #expect(lookedUp == "Looked up")
            #expect(note == expectedNote)
            #expect(try sut.inspect().find(button: "Copy as Text").isDisabled() == false)
            #expect(try sut.inspect().find(button: "Copy as CSV").isDisabled() == false)
        }

        @Test("Picking another language lists what it misses and offers -AppleLanguages for it; the filter narrows the list")
        func pickLanguageAndFilter() async throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: [
                        "a.title": LocalizationEntry("Alpha"), "b.title": LocalizationEntry("Beta"), "c.title": LocalizationEntry("Gamma")
                    ])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["a.title": LocalizationEntry("Ä"), "b.title": LocalizationEntry("B")])],
                    "fr": [LocalizationTable(name: "Localizable", entries: ["a.title": LocalizationEntry("À")])]
                ]
            )
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: [], onRefresh: {})

            try await ViewHosting.host(sut.environment(\.locale, Locale(identifier: "en_US"))) {
                try await sut.inspection.inspect { view in
                    let keys = try view.findAll(MissingTranslationRow.self).map { try $0.actualView().item.key }
                    #expect(keys == ["c.title"])
                    #expect(try view.find(text: "-AppleLanguages (de)").string() == "-AppleLanguages (de)")
                    try view.find(ViewType.Picker.self).select(value: "fr")
                }
                try await sut.inspection.inspect { view in
                    let keys = try view.findAll(MissingTranslationRow.self).map { try $0.actualView().item.key }
                    #expect(keys == ["b.title", "c.title"])
                    #expect(try view.find(text: "-AppleLanguages (fr)").string() == "-AppleLanguages (fr)")
                    try view.find(ViewType.TextField.self).setInput("gamma")
                }
                try await sut.inspection.inspect { view in
                    let keys = try view.findAll(MissingTranslationRow.self).map { try $0.actualView().item.key }
                    #expect(keys == ["c.title"])
                    try view.find(ViewType.TextField.self).setInput("zeta")
                }
                try await sut.inspection.inspect { view in
                    let note = try view.find(text: "No missing translation matches “zeta”.").string()
                    #expect(view.findAll(MissingTranslationRow.self).isEmpty)
                    #expect(note == "No missing translation matches “zeta”.")
                }
            }
        }

        @Test("The picker names each language in the drawer's locale, then its code")
        func languageNames() throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "en",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("Ä")])]
                ]
            )
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: [], onRefresh: {})
                .environment(\.locale, Locale(identifier: "en_US"))

            let german = try sut.inspect().find(text: "German (de)").string()
            let english = try sut.inspect().find(text: "English (en)").string()

            #expect(german == "German (de)")
            #expect(english == "English (en)")
        }

        @Test("In the development language with nothing looked up, nothing is missing, and there is nothing to copy")
        func developmentLanguage() throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "en",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])],
                    "de": []
                ]
            )
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: [], onRefresh: {})
            let expected = "en is the development language, and every string the app looked up is in its tables."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Copy as Text") }
            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.TextField.self) }
        }

        @Test("An app in one language says nothing can be missing, and offers no picker")
        func singleLanguage() throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "en",
                tables: ["en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])]]
            )
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: [], onRefresh: {})
            let expected = "The app's strings are in en only, so no translation can be missing. Add a language to its tables to compare."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.Picker.self) }
        }

        @Test("An app with no tables says so")
        func noTables() throws {
            let sut = LocalizationView(mode: .constant(.standard), bundles: [], lookups: [], onRefresh: {})
            let expected = "The app's bundles hold no .strings or .stringsdict table."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("Refresh reads the tables again")
        func refresh() throws {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])],
                    "de": [LocalizationTable(name: "Localizable", entries: [:])]
                ]
            )
            var refreshes = 0
            let sut = LocalizationView(mode: .constant(.standard), bundles: [bundle], lookups: [], onRefresh: { refreshes += 1 })

            try sut.inspect().find(button: "Refresh").tap()

            #expect(refreshes == 1)
        }

        @Test("Each launch argument is listed as code with a copy button that names it")
        func launchArguments() throws {
            let sut = LaunchArgumentsSection(language: "de")
            let expected = [
                "-NSDoubleLocalizedStrings YES", "-NSAccentuateLocalizedStrings YES", "-NSShowNonLocalizedStrings YES",
                "-NSForceRightToLeftWritingDirection YES", "-AppleLanguages (de)"
            ]

            let arguments = try sut.inspect().findAll(DebugDrawerCodeText.self).map { try $0.actualView().text }
            let copyLabels = try sut.inspect().findAll(DebugDrawerCopyButton.self).map { try $0.accessibilityLabel().string() }

            #expect(arguments == expected)
            #expect(copyLabels == expected.map { "Copy \($0)" })
        }

        @Test("The header counts what the current language misses, and shows nothing when nothing is")
        func headerAccessory() async throws {
            struct Fixed: LocalizationTableSource {
                func bundles() -> [LocalizedBundle] {
                    [LocalizedBundle(
                        name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                        tables: [
                            "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A"), "b": LocalizationEntry("B")])],
                            "de": [LocalizationTable(name: "Localizable", entries: [:])]
                        ]
                    )]
                }
            }
            let model = LocalizationModel(source: Fixed(), state: LocalizationState(appBundles: AppBundles(root: "/App.app")))
            let before = LocalizationHeaderAccessory(model: model)
            #expect(throws: (any Error).self) { try before.inspect().find(ViewType.Text.self) }

            await model.refresh()
            let actual = try LocalizationHeaderAccessory(model: model).inspect().find(ViewType.Text.self).string()

            #expect(actual == "2 missing")
        }

        @Test("A pending relaunch leads the header, and stored settings show as whole app once launched with")
        func headerNextLaunch() throws {
            let name = temporarySuiteName("LocalizationViewTests")
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            struct NoTables: LocalizationTableSource {
                func bundles() -> [LocalizedBundle] {
                    []
                }
            }
            let state = LocalizationState(appBundles: AppBundles(root: "/App.app"))
            let model = LocalizationModel(
                source: NoTables(), state: state, nextLaunchDefaults: NextLaunchDefaults(defaults: defaults, domainName: name)
            )
            model.setNextLaunch(.pseudoLocalized, isOn: true)
            let pending = try LocalizationHeaderAccessory(model: model).inspect().find(ViewType.Text.self).string()
            let relaunched = LocalizationModel(
                source: NoTables(), state: state, nextLaunchDefaults: NextLaunchDefaults(defaults: defaults, domainName: name)
            )

            let actual = try LocalizationHeaderAccessory(model: relaunched).inspect().find(ViewType.Text.self).string()

            #expect(pending == "relaunch to apply")
            #expect(actual == "whole app")
        }

        @Test("Each next-launch toggle reports its setting; a change shows Relaunch to apply, a launched setting how to undo it")
        func nextLaunchSection() throws {
            var changes: [String] = []
            let sut = LocalizationView(
                mode: .constant(.standard), bundles: [], lookups: [], nextLaunch: [], launchedWith: [],
                onNextLaunchChange: { changes.append("\($0.rawValue) \($1)") }, onRefresh: {}
            )

            try sut.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Accented and Doubled" }).tap()
            try sut.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Untranslated in Capitals" }).tap()
            let pending = try LocalizationView(
                mode: .constant(.standard), bundles: [], lookups: [], nextLaunch: [.pseudoLocalized], launchedWith: [], onRefresh: {}
            ).inspect()
            let launched = try LocalizationView(
                mode: .constant(.standard), bundles: [], lookups: [], nextLaunch: [.pseudoLocalized], launchedWith: [.pseudoLocalized], onRefresh: {}
            ).inspect()
            let unchanged = try LocalizationView(mode: .constant(.standard), bundles: [], lookups: [], onRefresh: {}).inspect()

            #expect(changes == ["pseudoLocalized true", "untranslatedInCapitals true"])
            #expect(try pending.find(text: "Relaunch to apply").string() == "Relaunch to apply")
            #expect(try pending.find(text: "Next launch: Accented and Doubled.").string() == "Next launch: Accented and Doubled.")
            #expect(try launched.find(text: "On in this launch").string() == "On in this launch")
            #expect(throws: (any Error).self) { try unchanged.find(text: "Relaunch to apply") }
            #expect(throws: (any Error).self) { try unchanged.find(text: "On in this launch") }
        }
    }
#endif
