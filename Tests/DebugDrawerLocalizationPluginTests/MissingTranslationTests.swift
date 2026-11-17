#if DEBUG
    @testable import DebugDrawerLocalizationPlugin
    import Testing

    @Suite
    struct MissingTranslationTests {
        @Test("A language misses each development key its table of the same name lacks, sorted by table and key")
        func staticGaps() {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [
                        LocalizationTable(name: "Localizable", entries: [
                            "settings.title": LocalizationEntry("Settings"), "privacy": LocalizationEntry("Privacy Policy"),
                            "orders.count": LocalizationEntry("%lld orders", isPlural: true)
                        ]),
                        LocalizationTable(name: "Checkout", entries: ["promo": LocalizationEntry("Have a promo code?")])
                    ],
                    "de": [LocalizationTable(name: "Localizable", entries: ["settings.title": LocalizationEntry("Einstellungen")])]
                ]
            )
            let expected = [
                MissingTranslation(group: "Checkout", key: "promo", developmentValue: "Have a promo code?", isLookedUp: false),
                MissingTranslation(group: "Localizable", key: "orders.count", developmentValue: "%lld orders", isLookedUp: false),
                MissingTranslation(group: "Localizable", key: "privacy", developmentValue: "Privacy Policy", isLookedUp: false)
            ]

            let actual = MissingTranslation.find(in: [bundle], localization: "de", lookups: [])

            #expect(actual == expected)
        }

        @Test("Base holds development text: its keys count against a translation, and as present for the development language")
        func base() {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "en",
                tables: [
                    "Base": [LocalizationTable(name: "Main", entries: ["title": LocalizationEntry("Orders")])],
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])],
                    "fr": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("À")])]
                ]
            )
            let expected = [MissingTranslation(group: "Main", key: "title", developmentValue: "Orders", isLookedUp: false)]

            let french = MissingTranslation.find(in: [bundle], localization: "fr", lookups: [])
            let english = MissingTranslation.find(in: [bundle], localization: "en", lookups: [])

            #expect(french == expected)
            #expect(english.isEmpty)
        }

        @Test("A looked-up key the language's table lacks is listed as looked up, with the development text or the default value")
        func lookups() {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: [
                        "privacy": LocalizationEntry("Privacy Policy"),
                        "ok": LocalizationEntry("OK")])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["ok": LocalizationEntry("OK")])]
                ]
            )
            let lookups = [
                LocalizationLookup(bundlePath: "/App.app", table: nil, key: "privacy", defaultValue: nil),
                LocalizationLookup(bundlePath: "/App.app", table: "", key: "banner.new", defaultValue: "New: faster checkout"),
                LocalizationLookup(bundlePath: "/App.app", table: "Errors", key: "error.unknown", defaultValue: ""),
                // In the table, so translated, though the translation is the key itself.
                LocalizationLookup(bundlePath: "/App.app", table: nil, key: "ok", defaultValue: nil),
                // Another bundle's.
                LocalizationLookup(bundlePath: "/Other.bundle", table: nil, key: "elsewhere", defaultValue: nil)
            ]
            let expected = [
                MissingTranslation(group: "Errors", key: "error.unknown", developmentValue: nil, isLookedUp: true),
                MissingTranslation(group: "Localizable", key: "banner.new", developmentValue: "New: faster checkout", isLookedUp: true),
                MissingTranslation(group: "Localizable", key: "privacy", developmentValue: "Privacy Policy", isLookedUp: true)
            ]

            let actual = MissingTranslation.find(in: [bundle], localization: "de", lookups: lookups)

            #expect(actual == expected)
        }

        @Test("A bundle other than the main one groups under its name; one with a single localization lacks nothing")
        func otherBundles() {
            let kit = LocalizedBundle(
                name: "Kit.framework", path: "/App.app/Frameworks/Kit.framework", isMain: false, developmentLocalization: "en",
                preferredLocalization: "en",
                tables: ["en": [LocalizationTable(name: "Kit", entries: ["retry": LocalizationEntry("Retry")])], "de": []]
            )
            let unlocalized = LocalizedBundle(
                name: "Assets.bundle", path: "/App.app/Assets.bundle", isMain: false, developmentLocalization: "en", preferredLocalization: "en",
                tables: ["en": [LocalizationTable(name: "Assets", entries: ["x": LocalizationEntry("X")])]]
            )
            let expected = [MissingTranslation(group: "Kit.framework · Kit", key: "retry", developmentValue: "Retry", isLookedUp: false)]

            let actual = MissingTranslation.find(in: [kit, unlocalized], localization: "de", lookups: [])

            #expect(actual == expected)
        }

        @Test("No bundles, or a complete translation, miss nothing")
        func nothingMissing() {
            let bundle = LocalizedBundle(
                name: "App.app", path: "/App.app", isMain: true, developmentLocalization: "en", preferredLocalization: "de",
                tables: [
                    "en": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("A")])],
                    "de": [LocalizationTable(name: "Localizable", entries: ["a": LocalizationEntry("Ä")])]
                ]
            )

            let none = MissingTranslation.find(in: [], localization: "de", lookups: [])
            let complete = MissingTranslation.find(in: [bundle], localization: "de", lookups: [])

            #expect(none.isEmpty)
            #expect(complete.isEmpty)
        }

        @Test("Missing translations copy as text grouped by table, and as CSV with fields quoted where they need it")
        func export() {
            let missing = [
                MissingTranslation(group: "Checkout", key: "delivery", developmentValue: "Delivery: %@, \"express\"", isLookedUp: false),
                MissingTranslation(group: "Localizable", key: "banner.new", developmentValue: "New: faster checkout", isLookedUp: true),
                MissingTranslation(group: "Localizable", key: "error.unknown", developmentValue: nil, isLookedUp: true)
            ]
            let expectedText = """
            Missing in de (3):
            Checkout
              delivery = "Delivery: %@, "express""
            Localizable
              banner.new = "New: faster checkout" (looked up)
              error.unknown (looked up)
            """
            let expectedCSV = [
                "table,key,development value,looked up",
                "Checkout,delivery,\"Delivery: %@, \"\"express\"\"\",no",
                "Localizable,banner.new,New: faster checkout,yes",
                "Localizable,error.unknown,,yes"
            ].joined(separator: "\r\n")

            let text = MissingTranslation.text(of: missing, language: "de")
            let csv = MissingTranslation.csv(of: missing)

            #expect(text == expectedText)
            #expect(csv == expectedCSV)
        }

        @Test("A lookup is untranslated when it returned the key or the default value it passed")
        func untranslated() {
            let returnedKey = LocalizationLookup.isUntranslated(key: "a.title", defaultValue: nil, result: "a.title")
            let returnedDefault = LocalizationLookup.isUntranslated(key: "a.title", defaultValue: "Title", result: "Title")
            let translated = LocalizationLookup.isUntranslated(key: "a.title", defaultValue: "Title", result: "Titel")
            let emptyDefault = LocalizationLookup.isUntranslated(key: "a.title", defaultValue: "", result: "")
            let emptyKey = LocalizationLookup.isUntranslated(key: "", defaultValue: nil, result: "")

            #expect(returnedKey)
            #expect(returnedDefault)
            #expect(!translated)
            #expect(!emptyDefault)
            #expect(!emptyKey)
        }

        @Test("App bundles are the main bundle and those inside it, except the drawer's own")
        func appBundles() {
            let sut = AppBundles(root: "/Apps/DebugDrawerExample.app/")

            #expect(sut.contains("/Apps/DebugDrawerExample.app"))
            #expect(sut.contains("/Apps/DebugDrawerExample.app/Frameworks/Kit.framework"))
            #expect(sut.contains("/Apps/DebugDrawerExample.app/Orders_Orders.bundle"))
            #expect(!sut.contains("/Apps/DebugDrawerExample.app/DebugDrawer_DebugDrawerConsolePlugin.bundle"))
            #expect(!sut.contains("/Apps/DebugDrawerExample.appendix"))
            #expect(!sut.contains("/System/Library/Frameworks/UIKit.framework"))
        }
    }
#endif
