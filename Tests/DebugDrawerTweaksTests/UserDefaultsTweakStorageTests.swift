import DebugDrawerTweaks
import Foundation
import Testing

@Suite
struct UserDefaultsTweakStorageTests {
    @Test("Booleans, integers and strings come back as the cases they were stored as")
    func roundTrip() throws {
        let suiteName = "com.debugdrawer.tests.tweak-storage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = UserDefaultsTweakStorage(defaults: defaults)

        sut.setValue(.bool(true), forKey: "flag")
        sut.setValue(.int(1), forKey: "count")
        sut.setValue(.string(""), forKey: "text")

        #expect(sut.value(forKey: "flag") == .bool(true))
        #expect(sut.value(forKey: "count") == .int(1))
        #expect(sut.value(forKey: "text") == .string(""))
        #expect(sut.value(forKey: "missing") == nil)
    }

    @Test("Storing nil removes the value")
    func remove() throws {
        let suiteName = "com.debugdrawer.tests.tweak-storage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = UserDefaultsTweakStorage(defaults: defaults, keyPrefix: "app.")
        sut.setValue(.int(3), forKey: "count")

        sut.setValue(nil, forKey: "count")

        #expect(sut.value(forKey: "count") == nil)
        #expect(defaults.object(forKey: "app.count") == nil)
    }

    @Test("Each key is stored behind the prefix")
    func prefix() throws {
        let suiteName = "com.debugdrawer.tests.tweak-storage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = UserDefaultsTweakStorage(defaults: defaults, keyPrefix: "app.")

        sut.setValue(.string("staging"), forKey: "server")

        #expect(defaults.string(forKey: "app.server") == "staging")
        #expect(UserDefaultsTweakStorage.defaultKeyPrefix == "com.debugdrawer.tweaks.")
    }

    @Test("A value of a type tweaks don't store reads as nothing")
    func foreignValue() throws {
        let suiteName = "com.debugdrawer.tests.tweak-storage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Date(), forKey: "com.debugdrawer.tweaks.when")
        let sut = UserDefaultsTweakStorage(defaults: defaults)

        let actual = sut.value(forKey: "when")

        #expect(actual == nil)
    }
}
