#if DEBUG
    import CoreTransferable
    @testable import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing
    import UniformTypeIdentifiers

    @Suite
    struct MetricKitPayloadTests {
        @Test("The JSON is shown indented with sorted keys and unescaped slashes")
        func formattedJSON() {
            let sut = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data(#"{"b":[1,2],"a":{"path":"a/b"}}"#.utf8), isSeen: false
            )
            let expected = """
            {
              "a" : {
                "path" : "a/b"
              },
              "b" : [
                1,
                2
              ]
            }
            """

            let actual = sut.formattedJSON

            #expect(actual == expected)
        }

        @Test("JSON that no longer parses is shown as it is")
        func formattedGarbage() {
            let sut = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data("not json".utf8), isSeen: false
            )

            let actual = sut.formattedJSON

            #expect(actual == "not json")
        }

        @Test("The export and report names hold the kind and the end of the period, without colons")
        func names() {
            let sut = MetricKitPayload(
                id: UUID(), kind: .diagnostics, begin: Date(timeIntervalSince1970: 1_763_164_800), end: Date(timeIntervalSince1970: 1_763_290_000),
                received: Date(timeIntervalSince1970: 1_763_290_000), json: Data("{}".utf8), isSeen: false
            )

            #expect(sut.exportFileName == "MetricKit diagnostics 2025-11-16T10-46-40Z.json")
            #expect(sut.reportName == "diagnostics 2025-11-16T10-46-40Z")
        }

        @Test("The period runs from begin to end, in order even when the timestamps weren't")
        func period() {
            let early = Date(timeIntervalSince1970: 1)
            let late = Date(timeIntervalSince1970: 2)
            let sut = MetricKitPayload(id: UUID(), kind: .metrics, begin: late, end: early, received: late, json: Data("{}".utf8), isSeen: false)

            let actual = sut.period

            #expect(actual == early ..< late)
        }

        // Transferable's export calls arrived in macOS 15.2 and iOS 18.2; earlier systems skip it.
        @available(macOS 15.2, iOS 18.2, *)
        @Test("Exported, the payload is a JSON file of its formatted JSON")
        func export() async throws {
            let payload = MetricKitPayload(
                id: UUID(), kind: .metrics, begin: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1),
                received: Date(timeIntervalSince1970: 1), json: Data(#"{"appVersion":"1.0"}"#.utf8), isSeen: false
            )
            let sut = MetricKitPayloadFile(payload: payload)
            let expected = payload.formattedJSONData

            let actual = try await sut.exported(as: .json)

            #expect(actual == expected)
            #expect(sut.exportedContentTypes() == [.json])
        }
    }
#endif
