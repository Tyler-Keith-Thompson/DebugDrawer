// The review's lookups in each mode, driven through the model's own commands. Each test makes a
// review of its own and a bundle in a folder of its own: an English table translating `greeting`
// and `farewell %@`, and a stringsdict whose `%lld items` has a variant per count.
import Combine
import DebugDrawerLocalization
import Foundation
import Testing

@MainActor
@Suite
struct LocalizationReviewTests {
    private func fixtureBundle() throws -> Bundle {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LocalizationReviewTests-\(UUID().uuidString)/Fixture.bundle", directoryHint: .isDirectory)
        let lproj = url.appending(path: "en.lproj", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try Data(#""greeting" = "Hello"; "farewell %@" = "Goodbye, %@";"#.utf8).write(to: lproj.appending(path: "Localizable.strings"))
        let plurals: [String: Any] = [
            "%lld items": [
                "NSStringLocalizedFormatKey": "%#@items@",
                "items": [
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "lld",
                    "one": "%lld item",
                    "other": "%lld items"
                ]
            ]
        ]
        try PropertyListSerialization.data(fromPropertyList: plurals, format: .xml, options: 0)
            .write(to: lproj.appending(path: "Localizable.stringsdict"))
        let info: [String: Any] = ["CFBundleIdentifier": "debugdrawer.tests.review.\(UUID().uuidString)", "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appending(path: "Info.plist"))
        return try #require(Bundle(url: url))
    }

    @Test("A new review shows each string as its table translates it")
    func standardByDefault() throws {
        let bundle = try fixtureBundle()
        let sut = LocalizationReview()

        let actual = sut.localizedString(forKey: "greeting", bundle: bundle)

        #expect(sut.mode == .standard)
        #expect(sut.snapshot == LocalizationReview.Snapshot(mode: .standard))
        #expect(actual == "Hello")
    }

    @Test("Showing keys returns the key; a key the table lacks still returns the default value's key")
    func showingKeys() throws {
        let bundle = try fixtureBundle()
        let sut = LocalizationReview()

        sut.perform(.setMode(.showingKeys))

        #expect(sut.localizedString(forKey: "greeting", bundle: bundle) == "greeting")
        #expect(sut.localizedString(forKey: "missing", value: "Fallback", bundle: bundle) == "missing")
    }

    @Test("Pseudo-localizing accents, pads and brackets the translation, and keeps its format specifiers")
    func pseudoLocalized() throws {
        let bundle = try fixtureBundle()
        let sut = LocalizationReview()

        sut.perform(.setMode(.pseudoLocalized))
        let format = sut.localizedString(forKey: "farewell %@", bundle: bundle)

        #expect(sut.localizedString(forKey: "greeting", bundle: bundle) == "[Ĥéļļö··]")
        #expect(format == "[Ĝööðƀýé, %@····]")
        #expect(String(format: format, "Ana") == "[Ĝööðƀýé, Ana····]")
    }

    @Test("A resource is resolved with its arguments and plural variant before the mode applies, and shows its key")
    func resource() throws {
        let bundle = try fixtureBundle()
        let sut = LocalizationReview()
        func items(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("\(count) items", table: "Localizable", locale: Locale(identifier: "en"), bundle: .atURL(bundle.bundleURL))
        }

        let standard = (sut.localizedString(items(1)), sut.localizedString(items(3)))
        sut.perform(.setMode(.pseudoLocalized))
        let pseudo = (sut.localizedString(items(1)), sut.localizedString(items(3)))
        sut.perform(.setMode(.showingKeys))
        let keys = sut.localizedString(items(3))

        #expect(standard.0 == "1 item")
        #expect(standard.1 == "3 items")
        #expect(pseudo.0 == "[1 îţéɱ···]")
        #expect(pseudo.1 == "[3 îţéɱš···]")
        #expect(keys == "%lld items")
    }

    @Test("Setting the mode it already has publishes nothing; setting standard again shows translations")
    func repeatedModes() throws {
        let bundle = try fixtureBundle()
        let sut = LocalizationReview()
        var published: [LocalizationReview.Snapshot] = []
        let subscription = sut.$snapshot.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }

        sut.perform(.setMode(.standard))
        sut.perform(.setMode(.showingKeys))
        sut.perform(.setMode(.showingKeys))
        sut.perform(.setMode(.standard))

        #expect(published.map(\.mode) == [.showingKeys, .standard])
        #expect(sut.localizedString(forKey: "greeting", bundle: bundle) == "Hello")
    }

    @Test("The empty key shows the translation even while showing keys, and the empty string stays empty pseudo-localized")
    func emptyStrings() throws {
        let bundle = try fixtureBundle()
        let sut = LocalizationReview()

        sut.perform(.setMode(.showingKeys))
        let emptyKey = sut.localizedString(forKey: "", value: "Shown", bundle: bundle)
        sut.perform(.setMode(.pseudoLocalized))
        let emptyValue = sut.localizedString(forKey: "missing", value: "", table: "Nowhere", bundle: bundle)

        #expect(emptyKey == "Shown")
        #expect(emptyValue == "[ɱîššîñĝ···]")
    }
}
