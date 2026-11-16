#if DEBUG
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @Suite
    struct AnalyticsEventSearchTests {
        @Test("The filter matches the name, the source, a key and a value, ignoring case and diacritics",
              arguments: ["checkout", "COMPLETED", "segment", "plan", "PRO", "29.99", "true", "Zürich", "zurich"])
        func matches(query: String) {
            let sut = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "checkout_completed",
                properties: ["plan": "pro", "total": 29.99, "trial": true, "city": "Zürich"], source: "Segment"
            )

            let actual = sut.matches(query)

            #expect(actual)
        }

        @Test("The filter matches keys and values nested in arrays and objects",
              arguments: ["sku-42", "quantity", "country", "NZ", "gift"])
        func matchesNested(query: String) {
            let sut = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "order_placed",
                properties: ["items": [["sku": "sku-42", "quantity": 2]], "shipping": ["address": ["country": "NZ"]], "tags": ["gift"]],
                source: nil
            )

            let actual = sut.matches(query)

            #expect(actual)
        }

        @Test("The filter matches a date as the drawer shows it, and null as null")
        func matchesDatesAndNull() {
            let sut = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "renewed",
                properties: ["renews": .date(Date(timeIntervalSince1970: 1_763_290_000)), "coupon": nil], source: nil
            )

            #expect(sut.matches("2025-11-16"))
            #expect(sut.matches("null"))
        }

        @Test("An empty filter, or one of spaces, matches every event", arguments: ["", "   ", "\n"])
        func emptyQuery(query: String) {
            let sut = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)

            let actual = sut.matches(query)

            #expect(actual)
        }

        @Test("Spaces around the filter are ignored")
        func trimmed() {
            let sut = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)

            let actual = sut.matches("  open ")

            #expect(actual)
        }

        @Test("The filter doesn't match what the event doesn't hold, nor the time it was recorded",
              arguments: ["signup", "enterprise", "1970", "Firebase", "seats"])
        func noMatch(query: String) {
            let sut = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "checkout_completed",
                properties: ["plan": "pro", "items": ["a"]], source: "Segment"
            )

            let actual = sut.matches(query)

            #expect(!actual)
        }
    }
#endif
