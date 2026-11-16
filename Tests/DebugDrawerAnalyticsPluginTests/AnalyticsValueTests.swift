import DebugDrawerAnalyticsPlugin
import Foundation
import Testing

@Suite
struct AnalyticsValueTests {
    @Test("Literals take their cases, nested ones too")
    func literals() {
        let expected: [String: AnalyticsValue] = [
            "plan": .string("pro"), "seats": .int(3), "total": .double(29.99), "trial": .bool(false), "coupon": .null,
            "items": .array([.string("sku-1"), .int(2)]), "shipping": .object(["country": .string("NZ")])
        ]

        let actual: [String: AnalyticsValue] = [
            "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
            "items": ["sku-1", 2], "shipping": ["country": "NZ"]
        ]

        #expect(actual == expected)
    }

    @Test("An interpolated string is a string")
    func interpolation() {
        let plan = "pro"
        let expected = AnalyticsValue.string("plan pro")

        let actual: AnalyticsValue = "plan \(plan)"

        #expect(actual == expected)
    }

    @Test("A dictionary literal that names a key twice keeps the last value")
    func duplicateKey() {
        let expected = AnalyticsValue.object(["a": .int(2)])

        // Called directly: SwiftLint rejects a literal that repeats a key.
        let actual = AnalyticsValue(dictionaryLiteral: ("a", 1), ("a", 2))

        #expect(actual == expected)
    }

    @Test("Empty array and dictionary literals are an empty array and an empty object")
    func emptyLiterals() {
        let array: AnalyticsValue = []
        let object: AnalyticsValue = [:]

        #expect(array == .array([]))
        #expect(object == .object([:]))
    }

    @Test("Converting keeps Booleans Booleans, bridged or not, and tells whole numbers from others")
    func convertingNumbers() {
        let values: [Any] = [true, NSNumber(value: false), 3, NSNumber(value: 7), Int64(-2), 2.5, Float(0.5), 3.0, UInt64.max]
        let expected: [AnalyticsValue] = [
            .bool(true), .bool(false), .int(3), .int(7), .int(-2), .double(2.5), .double(0.5), .double(3), .double(Double(UInt64.max))
        ]

        let actual = values.map(AnalyticsValue.init(converting:))

        #expect(actual == expected)
    }

    @Test("Converting reads strings, dates, nulls, URLs, UUIDs and optionals")
    func convertingScalars() throws {
        let date = Date(timeIntervalSince1970: 1_763_290_000)
        let uuid = try #require(UUID(uuidString: "70B89F27-1634-3580-A695-57CDB41D7743"))
        let missing: String? = nil
        let present: Int? = 4
        let values: [Any] = [
            "pro", "pro".dropFirst(), date, NSNull(), URL(filePath: "/tmp/a b"), uuid, missing as Any, present as Any, AnalyticsValue.int(1)
        ]
        let expected: [AnalyticsValue] = [
            .string("pro"), .string("ro"), .date(date), .null, .string("file:///tmp/a%20b"),
            .string("70B89F27-1634-3580-A695-57CDB41D7743"), .null, .int(4), .int(1)
        ]

        let actual = values.map(AnalyticsValue.init(converting:))

        #expect(actual == expected)
    }

    @Test("Converting reads arrays and dictionaries, nested, and other keys by their descriptions")
    func convertingContainers() {
        let value: [String: Any] = ["items": ["sku-1", 2, ["gift": true]], "counts": [1: "one"] as [AnyHashable: Any]]
        let expected = AnalyticsValue.object([
            "items": .array([.string("sku-1"), .int(2), .object(["gift": .bool(true)])]),
            "counts": .object(["1": .string("one")])
        ])

        let actual = AnalyticsValue(converting: value)

        #expect(actual == expected)
    }

    @Test("Converting anything else keeps its description")
    func convertingOther() {
        struct Plan: CustomStringConvertible {
            var description: String {
                "Plan.pro"
            }
        }
        let expected = AnalyticsValue.string("Plan.pro")

        let actual = AnalyticsValue(converting: Plan())

        #expect(actual == expected)
    }
}
