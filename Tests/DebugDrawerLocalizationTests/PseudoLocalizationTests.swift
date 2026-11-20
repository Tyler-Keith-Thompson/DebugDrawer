#if DEBUG
    @testable import DebugDrawerLocalization
    import Foundation
    import Testing

    @Suite
    struct PseudoLocalizationTests {
        @Test("A word is accented, padded by 40% rounded up and bracketed")
        func word() {
            let expected = "[Šéţţîñĝš····]"

            let actual = PseudoLocalization.transform("Settings")

            #expect(actual == expected)
        }

        @Test("Every ASCII letter has an accented form, and nothing else changes",
              arguments: zip(
                  ["abcdefghijklm", "nopqrstuvwxyz", "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "0123456789", " .,!?-_/:;'\"()", "é ü ß 日本 🙂"],
                  ["áƀçðéƒĝĥîĵķļɱ", "ñöþǫŕšţûṽŵẋýž", "ÅƁÇÐÉƑĜĤÎĴĶĻṀ", "ÑÖÞǪŔŠŢÛṼŴẊÝŽ", "0123456789", " .,!?-_/:;'\"()", "é ü ß 日本 🙂"]
              ))
        func accents(input: String, expectedAccented: String) {
            let actual = PseudoLocalization.transform(input, isBracketed: false)

            #expect(actual == expectedAccented)
        }

        @Test("The empty string stays empty")
        func empty() {
            let actual = PseudoLocalization.transform("")

            #expect(actual.isEmpty)
        }

        @Test("Padding is ceil(0.4 × n) for the boundaries of each step",
              arguments: zip([1, 2, 3, 4, 5, 6, 10, 11, 100], [1, 1, 2, 2, 2, 3, 4, 5, 40]))
        func padding(length: Int, expectedPadding: Int) {
            let input = String(repeating: "x", count: length)
            let expected = "[" + String(repeating: "ẋ", count: length) + String(repeating: "·", count: expectedPadding) + "]"

            let actual = PseudoLocalization.transform(input)

            #expect(actual == expected)
        }

        @Test("Format specifiers are kept as they are and don't count toward the padding",
              arguments: zip(
                  ["%@", "Hi %@", "%d of %d", "%1$@ and %2$@", "%lld items", "%.2f%%",
                   "%-5s|", "%#@items@", "%1$lld/%2$lld", "%5.1lf", "%*d", "%hhu", "%zu", "%'d", "%x%X%o"],
                  ["[%@]", "[Ĥî %@··]", "[%d öƒ %d··]", "[%1$@ áñð %2$@··]", "[%lld îţéɱš···]", "[%.2f%%]", "[%-5s|·]", "[%#@items@]",
                   "[%1$lld/%2$lld·]", "[%5.1lf]", "[%*d]", "[%hhu]", "[%zu]", "[%'d]", "[%x%X%o]"]
              ))
        func specifiers(input: String, expected: String) {
            let actual = PseudoLocalization.transform(input)

            #expect(actual == expected)
        }

        @Test("A % that starts no specifier is literal text; %#@ without a name is printf's %@",
              arguments: zip(
                  ["100%", "50%!", "%", "%y", "%#@unterminated", "%#@@"],
                  ["[100%··]", "[50%!··]", "[%·]", "[%ý·]", "[%#@ûñţéŕɱîñáţéð·····]", "[%#@@·]"]))
        func strayPercent(input: String, expected: String) {
            let actual = PseudoLocalization.transform(input)

            #expect(actual == expected)
        }

        @Test("The pseudo-localized format formats with the same arguments as the original")
        func formats() {
            let format = "%1$@ has %2$lld new messages (%3$.1f%%)"
            let expected = "[Ada ĥáš 3 ñéŵ ɱéššáĝéš (12.5%)·········]"

            let actual = String(format: PseudoLocalization.transform(format), "Ada", 3, 12.5)

            #expect(actual == expected)
        }

        @Test("The transform is deterministic")
        func deterministic() {
            let input = "Delivery: %@ (%lld items)"

            let first = PseudoLocalization.transform(input)
            let second = PseudoLocalization.transform(input)

            #expect(first == second)
        }

        @Test("A stringsdict entry brackets its format once and accents each variant, leaving its rule keys")
        func stringsdict() throws {
            let entry: [String: Any] = [
                "NSStringLocalizedFormatKey": "%#@orders@ waiting",
                "orders": [
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": "lld",
                    "one": "%lld order",
                    "other": "%lld orders"
                ] as [String: Any]
            ]

            let actual = PseudoLocalization.transform(stringsdictEntry: entry)

            let orders = try #require(actual["orders"] as? [String: Any])
            #expect(actual["NSStringLocalizedFormatKey"] as? String == "[%#@orders@ ŵáîţîñĝ····]")
            #expect(orders["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType")
            #expect(orders["NSStringFormatValueTypeKey"] as? String == "lld")
            #expect(orders["one"] as? String == "%lld öŕðéŕ")
            #expect(orders["other"] as? String == "%lld öŕðéŕš")
        }

        @Test("Device variants nested in a stringsdict are accented too")
        func stringsdictNested() throws {
            let entry: [String: Any] = [
                "NSStringLocalizedFormatKey": "%#@device@",
                "device": [
                    "NSStringFormatSpecTypeKey": "NSStringDeviceSpecificRuleType",
                    "iphone": "Tap",
                    "mac": ["one": "Click", "other": "Clicks"] as [String: Any]
                ] as [String: Any]
            ]

            let actual = PseudoLocalization.transform(stringsdictEntry: entry)

            let device = try #require(actual["device"] as? [String: Any])
            let mac = try #require(device["mac"] as? [String: Any])
            #expect(device["NSStringFormatSpecTypeKey"] as? String == "NSStringDeviceSpecificRuleType")
            #expect(device["iphone"] as? String == "Ţáþ")
            #expect(mac["one"] as? String == "Çļîçķ")
            #expect(mac["other"] as? String == "Çļîçķš")
        }
    }
#endif
