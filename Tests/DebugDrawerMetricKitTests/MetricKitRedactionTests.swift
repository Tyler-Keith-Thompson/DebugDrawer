#if DEBUG
    @testable import DebugDrawerMetricKit
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite
    struct MetricKitRedactionTests {
        @Test("The standard rules mask a crash's composed exception message and its arguments, and keep the format string and everything else")
        func standard() throws {
            let sut = MetricKitRedaction.standard

            let actual = try #require(sut.redact(MetricKitFixtures.crashDiagnosticPayload))

            let object = try #require(try JSONSerialization.jsonObject(with: actual) as? [String: Any])
            let crash = try #require((object["crashDiagnostics"] as? [[String: Any]])?.first)
            let metadata = try #require(crash["diagnosticMetaData"] as? [String: Any])
            let reason = try #require(metadata["objectiveCexceptionReason"] as? [String: Any])
            #expect(reason["composedMessage"] as? String == MetricKitRedaction.mask)
            #expect(reason["arguments"] as? String == MetricKitRedaction.mask)
            #expect(reason["formatString"] as? String == "Can't save the profile of %@")
            #expect(reason["exceptionName"] as? String == "NSInternalInconsistencyException")
            #expect(metadata["signal"] as? Int == 11)
            #expect(metadata["terminationReason"] as? String == "Namespace SIGNAL, Code 11 Segmentation fault: 11")
            #expect(crash["callStackTree"] != nil)
            #expect(actual.range(of: Data(MetricKitFixtures.crashCustomerEmail.utf8)) == nil)
        }

        @Test("A masked key is masked at any depth, inside arrays too, and an object under it whole")
        func anyDepth() throws {
            let json = Data(#"{"a":{"composedMessage":{"x":1}},"b":[{"arguments":["s"]},{"c":2}]}"#.utf8)
            let expected = Data(#"{"a":{"composedMessage":"[REDACTED]"},"b":[{"arguments":"[REDACTED]"},{"c":2}]}"#.utf8)
            let sut = MetricKitRedaction.standard

            let actual = sut.redact(json)

            #expect(actual == expected)
        }

        @Test("Keys match exactly, as MetricKit spells them")
        func exactKeys() {
            let json = Data(#"{"ComposedMessage":"kept","composedMessages":"kept"}"#.utf8)
            let sut = MetricKitRedaction.standard

            let actual = sut.redact(json)

            #expect(actual == json)
        }

        @Test("adding(keys:) masks the host's keys as well as the standard ones; none masks nothing")
        func addingAndNone() throws {
            let json = Data(#"{"composedMessage":"m","virtualMemoryRegionInfo":"v"}"#.utf8)
            let expectedAdded = Data(#"{"composedMessage":"[REDACTED]","virtualMemoryRegionInfo":"[REDACTED]"}"#.utf8)

            let added = MetricKitRedaction.standard.adding(keys: ["virtualMemoryRegionInfo"]).redact(json)
            let none = MetricKitRedaction.none.redact(json)
            let custom = MetricKitRedaction(keys: ["virtualMemoryRegionInfo"]).redact(json)

            #expect(added == expectedAdded)
            #expect(none == json)
            #expect(custom == Data(#"{"composedMessage":"m","virtualMemoryRegionInfo":"[REDACTED]"}"#.utf8))
        }

        @Test("JSON that isn't an object redacts to nil", arguments: ["[1]", "\"text\"", "3", "", "{"])
        func notAnObject(text: String) {
            let sut = MetricKitRedaction.standard

            let actual = sut.redact(Data(text.utf8))

            #expect(actual == nil)
        }
    }
#endif
