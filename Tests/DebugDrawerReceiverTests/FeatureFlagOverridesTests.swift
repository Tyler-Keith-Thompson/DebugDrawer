import DebugDrawerReceiver
import Foundation
import Testing

/// A flag service the test reads back, with an override of the host's own on one flag.
@MainActor
private final class FakeFlagAdapter: DebugDrawerFeatureFlagAdapter {
    let live: [String: DebugDrawerFeatureFlagValue]
    var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    init(_ live: [String: DebugDrawerFeatureFlagValue]) {
        self.live = live
    }

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        live.keys.sorted().map { DebugDrawerFeatureFlag(key: $0, value: overrides[$0] ?? live[$0]!) }
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

// The feature flag overrides capability's model, driven directly: what it lets a sidecar change.
@MainActor
struct FeatureFlagOverridesTests {
    @Test("An override of a listed flag, of the flag's kind, reaches the adapter and the snapshot")
    func overridesListedFlag() {
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false), "threshold": .number(50)])
        let sut = DebugDrawerFeatureFlagOverrides(adapter: adapter)
        let expected = DebugDrawerFeatureFlagOverrides.Snapshot(
            flags: [DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(false)), DebugDrawerFeatureFlag(key: "threshold", value: .number(25))],
            overriddenKeys: ["threshold"]
        )

        sut.perform(.setOverride(key: "threshold", value: .number(25)))

        #expect(sut.snapshot == expected)
    }

    @Test("An override of a flag the adapter doesn't list, or of another kind than the flag's, changes nothing")
    func ignoresUnlistedAndWrongKind() {
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let sut = DebugDrawerFeatureFlagOverrides(adapter: adapter)
        let expected = sut.snapshot

        sut.perform(.setOverride(key: "api-token", value: .string("leaked")))
        sut.perform(.setOverride(key: "new-checkout", value: .string("true")))

        #expect(adapter.overrides.isEmpty)
        #expect(sut.snapshot == expected)
    }

    @Test("Clearing removes only the overrides the model set, never the host's own")
    func clearsOnlyItsOwn() {
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false), "promo": .bool(true)])
        adapter.overrides["promo"] = .bool(false)
        let sut = DebugDrawerFeatureFlagOverrides(adapter: adapter)
        let expected: [String: DebugDrawerFeatureFlagValue] = ["promo": .bool(false)]

        sut.perform(.setOverride(key: "new-checkout", value: .bool(true)))
        sut.perform(.clearOverride(key: "promo"))
        sut.perform(.clearAllOverrides)

        #expect(adapter.overrides == expected)
        #expect(sut.snapshot.overriddenKeys.isEmpty)
    }

    @Test("A value encodes as the bare JSON value and decodes back to its kind", arguments: [
        (DebugDrawerFeatureFlagValue.bool(true), "true"),
        (DebugDrawerFeatureFlagValue.number(0.25), "0.25"),
        (DebugDrawerFeatureFlagValue.string("blue"), "\"blue\"")
    ])
    func valueCoding(value: DebugDrawerFeatureFlagValue, json: String) throws {
        let encoded = try JSONEncoder().encode(value)

        let actual = try JSONDecoder().decode(DebugDrawerFeatureFlagValue.self, from: Data(json.utf8))

        #expect(String(bytes: encoded, encoding: .utf8) == json)
        #expect(actual == value)
    }
}
