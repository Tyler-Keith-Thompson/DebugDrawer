@testable import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

// The allowlist's declarations and values on their own: how a value crosses as JSON, which values
// each kind takes at the edges of its bounds, and how a stored object reads as each kind, so a key
// never hands a sidecar a value of a kind the host didn't declare.
@Suite
struct UserDefaultsTests {
    @Test("A value encodes as a one-key object naming its kind", arguments: [
        (DebugDrawerUserDefaultsValue.string("pro"), #"{"string":"pro"}"#),
        (.integer(3), #"{"integer":3}"#),
        (.double(0.5), #"{"double":0.5}"#),
        (.bool(true), #"{"bool":true}"#)
    ])
    func valueEncodes(_ value: DebugDrawerUserDefaultsValue, expected: String) throws {
        let data = try JSONEncoder().encode(value)

        #expect(String(bytes: data, encoding: .utf8) == expected)
        #expect(try JSONDecoder().decode(DebugDrawerUserDefaultsValue.self, from: data) == value)
    }

    @Test("A double that JSON writes as a whole number still decodes as a double")
    func wholeDoubleKeepsItsKind() throws {
        let data = try JSONEncoder().encode(DebugDrawerUserDefaultsValue.double(3))

        let actual = try JSONDecoder().decode(DebugDrawerUserDefaultsValue.self, from: data)

        #expect(actual == .double(3))
    }

    @Test("An object naming no kind, two kinds, or a value of another kind doesn't decode", arguments: [
        #"{}"#, #"{"string":"a","bool":true}"#, #"{"integer":"3"}"#, #"{"date":0}"#, #""pro""#
    ])
    func malformedValueDoesNotDecode(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DebugDrawerUserDefaultsValue.self, from: Data(json.utf8))
        }
    }

    @Test("Each kind takes values of its kind within its bounds, the bounds included, and nothing else")
    func kindsAcceptWithinBounds() {
        let string = DebugDrawerUserDefaultsKey.string("greeting", maximumLength: 3).kind
        let integer = DebugDrawerUserDefaultsKey.integer("items", in: 10 ... 100).kind
        let double = DebugDrawerUserDefaultsKey.double("discount", in: 0 ... 0.5).kind
        let bool = DebugDrawerUserDefaultsKey.bool("tips").kind
        let choice = DebugDrawerUserDefaultsKey.choice("plan", options: ["free", "pro"]).kind

        let accepted = [
            string.accepts(.string("")), string.accepts(.string("abc")),
            integer.accepts(.integer(10)), integer.accepts(.integer(100)),
            double.accepts(.double(0)), double.accepts(.double(0.5)),
            bool.accepts(.bool(false)),
            choice.accepts(.string("free")), choice.accepts(.string("pro"))
        ]
        let refused = [
            string.accepts(.string("abcd")), string.accepts(.integer(1)),
            integer.accepts(.integer(9)), integer.accepts(.integer(101)), integer.accepts(.double(20)),
            double.accepts(.double(-0.01)), double.accepts(.double(0.51)), double.accepts(.double(.nan)), double.accepts(.integer(0)),
            bool.accepts(.integer(1)), bool.accepts(.string("true")),
            choice.accepts(.string("Pro")), choice.accepts(.string("")), choice.accepts(.bool(true))
        ]

        #expect(!accepted.contains(false))
        #expect(!refused.contains(true))
    }

    @Test("A stored object reads as the key's kind only; another kind, or a number that isn't finite, reads as none")
    func objectsReadAsTheirKind() {
        let string = DebugDrawerUserDefaultsKey.string("greeting").kind
        let integer = DebugDrawerUserDefaultsKey.integer("items").kind
        let double = DebugDrawerUserDefaultsKey.double("discount").kind
        let bool = DebugDrawerUserDefaultsKey.bool("tips").kind
        let choice = DebugDrawerUserDefaultsKey.choice("plan", options: ["free"]).kind

        let actual: [DebugDrawerUserDefaultsValue?] = [
            string.value(of: "Hi"), string.value(of: Data([1])), string.value(of: nil),
            // UserDefaults hands numbers back as NSNumber.
            integer.value(of: NSNumber(value: 7)), integer.value(of: NSNumber(value: 2.5)), integer.value(of: "7"),
            double.value(of: NSNumber(value: 0.25)), double.value(of: NSNumber(value: 2)),
            double.value(of: NSNumber(value: Double.infinity)), double.value(of: NSNumber(value: Double.nan)),
            bool.value(of: true), bool.value(of: "YES"), bool.value(of: ["tips"]),
            // A choice reads whatever string is stored, an option or not: the key is allowlisted.
            choice.value(of: "enterprise")
        ]
        let expected: [DebugDrawerUserDefaultsValue?] = [
            .string("Hi"), nil, nil,
            .integer(7), nil, nil,
            .double(0.25), .double(2), nil, nil,
            .bool(true), nil, nil,
            .string("enterprise")
        ]

        #expect(actual == expected)
    }

    @Test("A key's title is its key unless the host names it")
    func titleDefaultsToKey() {
        let untitled = DebugDrawerUserDefaultsKey.bool("showsTips")
        let titled = DebugDrawerUserDefaultsKey.bool("showsTips", title: "Shows Tips")

        #expect([untitled.title, titled.title] == ["showsTips", "Shows Tips"])
    }

    @Test("An empty allowlist lists nothing, and every edit is notExposed")
    @MainActor
    func emptyAllowlistListsNothing() throws {
        let suite = temporarySuiteName("UserDefaultsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pro", forKey: "plan")

        let sut = try DebugDrawerUserDefaults(defaults: defaults)

        #expect(sut.snapshot == DebugDrawerUserDefaults.Snapshot(entries: [], editedKeys: []))
        #expect(sut.refusal(of: .set(key: "plan", value: .string("free"))) == .notExposed)
        #expect(sut.refusal(of: .remove(key: "plan")) == .notExposed)
    }

    @Test("A key edited twice is put back as it was before the first edit")
    @MainActor
    func revertPutsBackTheFirstOriginal() throws {
        let suite = temporarySuiteName("UserDefaultsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([9, 9]), forKey: "greeting")
        let sut = try DebugDrawerUserDefaults(.string("greeting"), defaults: defaults)
        sut.perform(.set(key: "greeting", value: .string("Hi")))
        sut.perform(.set(key: "greeting", value: .string("Hello")))

        let changes = sut.apply(.revertAll)

        // The original is put back whatever its kind, while the audit shows only the declared kind.
        #expect(defaults.data(forKey: "greeting") == Data([9, 9]))
        #expect(changes == [.init(key: "greeting", oldValue: .string("Hello"), newValue: nil)])
        #expect(sut.snapshot.editedKeys.isEmpty)
    }
}
