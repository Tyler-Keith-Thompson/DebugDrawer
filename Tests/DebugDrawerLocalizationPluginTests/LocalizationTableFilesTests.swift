#if DEBUG
    @testable import DebugDrawerLocalizationPlugin
    import Foundation
    import Testing

    @Suite
    struct LocalizationTableFilesTests {
        @Test("Text .strings in UTF-8 and UTF-16, binary .strings and a .stringsdict are read, a stringsdict winning for a key in both")
        func formats() throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: "LocalizationTableFilesTests-\(UUID().uuidString)/de.lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            try Data("/* Settings */\n\"settings.title\" = \"Einstellungen\";\n\"orders.count\" = \"stale\";\n".utf8)
                .write(to: folder.appending(path: "Localizable.strings"))
            try #require("\"welcome\" = \"Willkommen\";".data(using: .utf16)).write(to: folder.appending(path: "Onboarding.strings"))
            try PropertyListSerialization.data(fromPropertyList: ["save": "Sichern"], format: .binary, options: 0)
                .write(to: folder.appending(path: "Compiled.strings"))
            let plural: [String: Any] = [
                "orders.count": [
                    "NSStringLocalizedFormatKey": "%#@orders@ offen",
                    "orders": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld",
                               "one": "%lld Bestellung", "other": "%lld Bestellungen"]
                ]
            ]
            try PropertyListSerialization.data(fromPropertyList: plural, format: .xml, options: 0)
                .write(to: folder.appending(path: "Localizable.stringsdict"))
            try Data("not a table".utf8).write(to: folder.appending(path: "Broken.strings"))
            try Data("ignored".utf8).write(to: folder.appending(path: "Main.storyboardc"))
            let expected = [
                LocalizationTable(name: "Compiled", entries: ["save": LocalizationEntry("Sichern")]),
                LocalizationTable(name: "Localizable", entries: [
                    "settings.title": LocalizationEntry("Einstellungen"),
                    "orders.count": LocalizationEntry("%lld Bestellungen offen", isPlural: true)
                ]),
                LocalizationTable(name: "Onboarding", entries: ["welcome": LocalizationEntry("Willkommen")])
            ]

            let actual = LocalizationTableFiles.tables(in: folder)

            #expect(actual == expected)
        }

        @Test("An empty or missing folder has no tables")
        func emptyFolder() throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: "LocalizationTableFilesTests-\(UUID().uuidString)/en.lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

            let empty = LocalizationTableFiles.tables(in: folder)
            let missing = LocalizationTableFiles.tables(in: folder.appending(path: "nothing.lproj"))

            #expect(empty.isEmpty)
            #expect(missing.isEmpty)
        }

        @Test("A bundle's tables are read from each .lproj folder, with its development and preferred localizations")
        func bundle() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "LocalizationTableFilesTests-\(UUID().uuidString)/Kit.bundle")
            for (localization, strings) in [("en", "\"a\" = \"A\";\n\"b\" = \"B\";"), ("de", "\"a\" = \"Ä\";"), ("Base", "\"title\" = \"Title\";")] {
                let folder = root.appending(path: "\(localization).lproj")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data(strings.utf8).write(to: folder.appending(path: "Localizable.strings"))
            }
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "test.kit.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"], format: .xml, options: 0
            )
            .write(to: root.appending(path: "Info.plist"))
            defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
            let bundle = try #require(Bundle(url: root))

            let actual = BundleTableSource.read(bundle, isMain: false)

            #expect(actual.name == "Kit.bundle")
            #expect(actual.path == root.standardizedFileURL.path)
            #expect(!actual.isMain)
            #expect(actual.developmentLocalization == "en")
            #expect(actual.localizations == ["de", "en"])
            #expect(actual.tables["Base"]?.first?.entries == ["title": LocalizationEntry("Title")])
            #expect(actual.developmentTables.first?.entries.keys.sorted() == ["a", "b", "title"])
            #expect(actual.preferredLocalization.map(["de", "en"].contains) == true)
        }
    }
#endif
