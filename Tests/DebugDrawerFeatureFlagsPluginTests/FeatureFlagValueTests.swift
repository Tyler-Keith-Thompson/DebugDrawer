import DebugDrawerFeatureFlagsPlugin
import Foundation
import Testing

@Suite
struct FeatureFlagValueTests {
    @Test("A value describes itself alone, a whole number without a fraction", arguments: [
        (FeatureFlagValue.bool(true), "true"),
        (.number(3), "3"),
        (.number(-2), "-2"),
        (.number(0.25), "0.25"),
        (.number(1e20), "1e+20"),
        (.string("blue"), "blue"),
        (.string(""), "")
    ])
    func description(value: FeatureFlagValue, expected: String) {
        let actual = value.description

        #expect(actual == expected)
    }

    @Test("Values encode as bare JSON values")
    func encodes() throws {
        let values: [String: FeatureFlagValue] = ["a": .bool(false), "b": .number(0.5), "c": .string("x")]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expected = #"{"a":false,"b":0.5,"c":"x"}"#

        let actual = try String(bytes: encoder.encode(values), encoding: .utf8)

        #expect(actual == expected)
    }

    @Test("JSON true decodes as a Boolean, 1 as a number and \"true\" as a string")
    func decodesKinds() throws {
        let json = Data(#"{"bool":true,"number":1,"string":"true"}"#.utf8)
        let expected: [String: FeatureFlagValue] = ["bool": .bool(true), "number": .number(1), "string": .string("true")]

        let actual = try JSONDecoder().decode([String: FeatureFlagValue].self, from: json)

        #expect(actual == expected)
    }

    @Test("A JSON value that is none of the three kinds fails to decode")
    func rejectsOtherKinds() {
        let json = Data(#"{"list":[1,2]}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([String: FeatureFlagValue].self, from: json)
        }
    }
}
