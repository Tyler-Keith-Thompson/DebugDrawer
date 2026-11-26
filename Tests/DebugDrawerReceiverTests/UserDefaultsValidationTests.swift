// What the allowlist refuses as it is made: keys that contradict themselves or reach for
// DebugDrawer's own. Real in every build, so these run in debug and release alike.
import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

@MainActor
@Suite
struct UserDefaultsValidationTests {
    @Test("An allowlisted key that is empty throws emptyKey")
    func emptyKey() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.emptyKey

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.bool(""))
        }
    }

    @Test("An allowlisted key prefixed DebugDrawer. throws reservedKey, so a sidecar can't edit the capability's own record")
    func ownRecordKey() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.reservedKey

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.string("DebugDrawer.UserDefaults.originalValues"))
        }
    }

    @Test("An allowlisted key prefixed com.debugdrawer. throws reservedKey")
    func libraryKey() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.reservedKey

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.bool("com.debugdrawer.drawer.pinned"))
        }
    }

    @Test("A key that only starts with the letters DebugDrawer, without the dot, is the app's own and is taken")
    func keyStartingWithLibraryName() throws {
        let suite = temporarySuiteName("UserDefaultsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = ["DebugDrawerTips"]

        let sut = try DebugDrawerUserDefaults(.bool("DebugDrawerTips"), defaults: defaults)

        #expect(sut.snapshot.entries.map(\.key) == expected)
    }

    @Test("A string key whose maximum length is 0 throws maximumLengthNotPositive")
    func zeroMaximumLength() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.maximumLengthNotPositive

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.string("greeting", maximumLength: 0))
        }
    }

    @Test("A string key whose maximum length is negative throws maximumLengthNotPositive")
    func negativeMaximumLength() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.maximumLengthNotPositive

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.string("greeting", maximumLength: -1))
        }
    }

    @Test("A string key of maximum length 1 is taken: the edge of the valid range")
    func smallestMaximumLength() throws {
        let suite = temporarySuiteName("UserDefaultsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = DebugDrawerUserDefaultsKey.Kind.string(maximumLength: 1)

        let sut = try DebugDrawerUserDefaults(.string("initial", maximumLength: 1), defaults: defaults)

        #expect(sut.snapshot.entries.map(\.kind) == [expected])
    }

    @Test("A number key with an infinite upper bound throws boundNotFinite")
    func infiniteUpperBound() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.boundNotFinite

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.double("discount", in: 0 ... .infinity))
        }
    }

    @Test("A number key with an infinite lower bound throws boundNotFinite")
    func infiniteLowerBound() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.boundNotFinite

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.double("discount", in: -.infinity ... 0))
        }
    }

    @Test("A number key over the whole finite range, its default, is taken: the edge of the valid range")
    func widestFiniteRange() throws {
        let suite = temporarySuiteName("UserDefaultsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = DebugDrawerUserDefaultsKey.Kind.double(range: -Double.greatestFiniteMagnitude ... Double.greatestFiniteMagnitude)

        let sut = try DebugDrawerUserDefaults(.double("discount"), defaults: defaults)

        #expect(sut.snapshot.entries.map(\.kind) == [expected])
    }

    @Test("A choice key without options throws noOptions")
    func choiceWithoutOptions() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.noOptions

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.choice("plan", options: []))
        }
    }

    @Test("A choice key whose options repeat throws repeatedOption")
    func repeatedOption() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.repeatedOption

        #expect(throws: expected) {
            _ = try DebugDrawerUserDefaults(.choice("plan", options: ["free", "free"]))
        }
    }

    @Test("A choice key of one option is taken: the edge of the valid range")
    func oneOption() throws {
        let suite = temporarySuiteName("UserDefaultsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = DebugDrawerUserDefaultsKey.Kind.choice(options: ["free"])

        let sut = try DebugDrawerUserDefaults(.choice("plan", options: ["free"]), defaults: defaults)

        #expect(sut.snapshot.entries.map(\.kind) == [expected])
    }

    @Test("An allowlist listing one key twice, even as two kinds, throws duplicateKey")
    func repeatedKey() {
        let expected = DebugDrawerUserDefaults.InvalidKeys.duplicateKey

        #expect(throws: expected) {
            _ = try DebugDrawerReceiverCapability.userDefaults(.bool("showsTips"), .string("showsTips"))
        }
    }

    @Test("An empty allowlist is taken and lists nothing")
    func emptyAllowlist() throws {
        let suite = temporarySuiteName("UserDefaultsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let sut = try DebugDrawerUserDefaults(defaults: defaults)

        #expect(sut.snapshot.entries.isEmpty)
    }
}
