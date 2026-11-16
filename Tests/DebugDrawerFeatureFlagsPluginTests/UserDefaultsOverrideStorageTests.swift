import DebugDrawerFeatureFlagsPlugin
import Foundation
import Testing

@Suite
struct UserDefaultsOverrideStorageTests {
    @Test("Overrides persist under the storage's key, and another storage over the same defaults reads them")
    func persists() throws {
        let suiteName = "com.debugdrawer.tests.featureFlags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected: [String: FeatureFlagValue] = ["newCheckout": .bool(true), "discount": .number(0.15), "theme": .string("dark")]
        let launch = UserDefaultsFeatureFlagOverrideStorage(defaults: defaults)
        launch.setOverride(.bool(true), forKey: "newCheckout")
        launch.setOverride(.number(0.15), forKey: "discount")
        launch.setOverride(.string("dark"), forKey: "theme")
        let sut = UserDefaultsFeatureFlagOverrideStorage(defaults: defaults)

        let actual = sut.overrides()

        #expect(actual == expected)
        #expect(defaults.data(forKey: "com.debugdrawer.featureFlags.overrides") != nil)
        #expect(defaults.object(forKey: "newCheckout") == nil)
    }

    @Test("Removing one override keeps the others, and removing the last removes the defaults key")
    func removes() throws {
        let suiteName = "com.debugdrawer.tests.featureFlags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = UserDefaultsFeatureFlagOverrideStorage(defaults: defaults, key: "overrides")
        sut.setOverride(.bool(true), forKey: "a")
        sut.setOverride(.bool(false), forKey: "b")

        sut.setOverride(nil, forKey: "a")
        let afterOne = sut.overrides()
        sut.setOverride(nil, forKey: "b")

        #expect(afterOne == ["b": .bool(false)])
        #expect(sut.overrides().isEmpty)
        #expect(defaults.object(forKey: "overrides") == nil)
    }

    @Test("Nothing stored, or data that isn't an object of flag values, reads as no overrides")
    func unreadable() throws {
        let suiteName = "com.debugdrawer.tests.featureFlags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = UserDefaultsFeatureFlagOverrideStorage(defaults: defaults, key: "overrides")
        let empty = sut.overrides()
        defaults.set(Data("not json".utf8), forKey: "overrides")

        let actual = sut.overrides()

        #expect(empty.isEmpty)
        #expect(actual.isEmpty)
    }
}
