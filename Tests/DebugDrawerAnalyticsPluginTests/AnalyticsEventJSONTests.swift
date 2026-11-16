#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @Suite
    struct AnalyticsEventJSONTests {
        @Test("An event's JSON has sorted keys, the source, and dates in ISO 8601 with milliseconds in UTC")
        func formatted() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 1_763_290_000.25), name: "checkout_completed",
                properties: ["seats": 3, "plan": "pro", "trial": false, "total": 29.99, "renews": .date(Date(timeIntervalSince1970: 0))],
                source: "Segment"
            )
            let expected = """
            {
              "name" : "checkout_completed",
              "properties" : {
                "plan" : "pro",
                "renews" : "1970-01-01T00:00:00.000Z",
                "seats" : 3,
                "total" : 29.99,
                "trial" : false
              },
              "source" : "Segment",
              "timestamp" : "2025-11-16T10:46:40.250Z"
            }
            """

            let actual = event.formattedJSON

            #expect(actual == expected)
        }

        @Test("An event with no source leaves the key out, and no properties is an empty object")
        func noSourceNoProperties() {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: nil)
            let expected = """
            {
              "name" : "opened",
              "properties" : {

              },
              "timestamp" : "1970-01-01T00:00:00.000Z"
            }
            """

            let actual = event.formattedJSON

            #expect(actual == expected)
        }

        @Test("Nested arrays and objects are written nested, with sorted keys, and null as null")
        func nested() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "cart",
                properties: ["items": [["sku": "a", "qty": 2], []], "coupon": nil, "meta": ["z": [:], "a": [1.5, true]]],
                source: nil
            )
            let expected = """
            {
              "name" : "cart",
              "properties" : {
                "coupon" : null,
                "items" : [
                  {
                    "qty" : 2,
                    "sku" : "a"
                  },
                  [

                  ]
                ],
                "meta" : {
                  "a" : [
                    1.5,
                    true
                  ],
                  "z" : {

                  }
                }
              },
              "timestamp" : "1970-01-01T00:00:00.000Z"
            }
            """

            let actual = event.formattedJSON

            #expect(actual == expected)
        }

        @Test("Quotes, backslashes, newlines, slashes, emoji and control characters are escaped as JSON needs, and nothing more")
        func specialCharacters() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "say \"hi\"",
                properties: ["text": "line\nbreak\ttab \\ / 🎉 é \u{1}"], source: nil
            )
            let expected = #"""
            {
              "name" : "say \"hi\"",
              "properties" : {
                "text" : "line\nbreak\ttab \\ / 🎉 é \u0001"
              },
              "timestamp" : "1970-01-01T00:00:00.000Z"
            }
            """#

            let actual = event.formattedJSON

            #expect(actual == expected)
        }

        @Test("Infinities and NaN, which JSON can't hold, are written as strings")
        func nonFinite() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "n",
                properties: ["a": .double(.infinity), "b": .double(-.infinity), "c": .double(.nan)], source: nil
            )
            let expected = """
            {
              "name" : "n",
              "properties" : {
                "a" : "Infinity",
                "b" : "-Infinity",
                "c" : "NaN"
              },
              "timestamp" : "1970-01-01T00:00:00.000Z"
            }
            """

            let actual = event.formattedJSON

            #expect(actual == expected)
        }

        @Test("Redaction masks sensitive keys, nested too, and the configured paths, keeping the indentation")
        func redacted() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "signed_in",
                properties: ["auth_token": "t0k3n", "user": ["email": "a@example.com", "password": "x"], "plan": "pro"], source: nil
            )
            let redaction = DebugDrawerRedaction.standard.adding(jsonPaths: ["properties.user.email"])
            let expected = """
            {
              "name" : "signed_in",
              "properties" : {
                "auth_token" : "[REDACTED]",
                "plan" : "pro",
                "user" : {
                  "email" : "[REDACTED]",
                  "password" : "[REDACTED]"
                }
              },
              "timestamp" : "1970-01-01T00:00:00.000Z"
            }
            """

            let actual = event.formattedJSON(redaction: redaction)

            #expect(actual == expected)
        }

        @Test("Redaction keeps every number as written, and reaches paths through arrays and wildcards")
        func redactedPaths() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "order",
                properties: ["total": 29.99, "items": [["sku": "a", "price": 0.1]], "user": ["phone": "555"]], source: nil
            )
            let redaction = DebugDrawerRedaction.none.adding(jsonPaths: ["properties.items.sku", "properties.*.phone"])
            let expected = """
            {
              "name" : "order",
              "properties" : {
                "items" : [
                  {
                    "price" : 0.1,
                    "sku" : "[REDACTED]"
                  }
                ],
                "total" : 29.99,
                "user" : {
                  "phone" : "[REDACTED]"
                }
              },
              "timestamp" : "1970-01-01T00:00:00.000Z"
            }
            """

            let actual = event.formattedJSON(redaction: redaction)

            #expect(actual == expected)
        }

        @Test("A path from the event's root doesn't mask the event's own name or time, nor a property it doesn't name")
        func redactionKeepsEventFields() {
            let event = AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "order", properties: ["name": "Ada"], source: "S")
            let redaction = DebugDrawerRedaction.none.adding(jsonPaths: ["name", "source", "timestamp"])

            let actual = event.redacted(by: redaction)

            #expect(actual == event)
        }

        @Test("With nothing to mask the redacted JSON is the JSON itself")
        func nothingToRedact() {
            let event = AnalyticsEvent(
                id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: ["plan": "pro", "total": 0.1], source: nil
            )
            let expected = event.formattedJSON

            let actual = event.formattedJSON(redaction: .standard)

            #expect(actual == expected)
        }

        @Test("Events are written as an array in the order given")
        func array() {
            let events = [
                AnalyticsEvent(id: 2, timestamp: Date(timeIntervalSince1970: 1), name: "second", properties: [:], source: nil),
                AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "first", properties: ["a": 1], source: "Firebase")
            ]
            let expected = """
            [
              {
                "name" : "second",
                "properties" : {

                },
                "timestamp" : "1970-01-01T00:00:01.000Z"
              },
              {
                "name" : "first",
                "properties" : {
                  "a" : 1
                },
                "source" : "Firebase",
                "timestamp" : "1970-01-01T00:00:00.000Z"
              }
            ]
            """

            let actual = AnalyticsEvent.formattedJSON(of: events, redaction: .none)

            #expect(actual == expected)
        }

        @Test("No events are an empty array")
        func emptyArray() {
            let expected = "[\n\n]"

            let actual = AnalyticsEvent.formattedJSON(of: [], redaction: .standard)

            #expect(actual == expected)
        }

        @Test("A value shows beside its key as itself, as JSON writes it, or as compact JSON")
        func displayText() {
            let values: [AnalyticsValue] = [
                "pro", 3, 2.5, true, nil, .date(Date(timeIntervalSince1970: 0)), ["a", 1], ["b": ["c": 1], "a": "x"], ""
            ]
            let expected = ["pro", "3", "2.5", "true", "null", "1970-01-01T00:00:00.000Z", #"["a",1]"#, #"{"a":"x","b":{"c":1}}"#, ""]

            let actual = values.map(\.displayText)

            #expect(actual == expected)
        }
    }
#endif
