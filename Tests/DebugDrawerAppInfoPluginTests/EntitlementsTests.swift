#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("Entitlements")
    struct EntitlementsTests {
        @Test("Common keys get word labels; any other key is its own label")
        func wordLabels() {
            let expected = [
                "com.apple.developer.associated-domains": "Associated domains",
                "com.apple.security.application-groups": "App groups",
                "keychain-access-groups": "Keychain access groups",
                "com.apple.security.app-sandbox": "App sandbox",
                "get-task-allow": "Get task allow",
                "com.apple.security.get-task-allow": "Get task allow",
                "com.example.custom": "com.example.custom"
            ]

            for (key, label) in expected.sorted(by: { $0.key < $1.key }) {
                let actual = Entitlement(key: key, value: .boolean(true)).label
                #expect(actual == label, "\(key)")
            }
        }

        @Test("Associated domains come first, then the other named keys in order, then the rest by key")
        func order() {
            let dictionary: [String: Any] = [
                "com.example.zeta": true,
                "com.apple.security.app-sandbox": true,
                "com.example.alpha": true,
                "keychain-access-groups": ["TEAM.*"],
                "com.apple.developer.associated-domains": ["applinks:example.com"],
                "com.apple.security.application-groups": ["group.com.example"]
            ]
            let expected = [
                "com.apple.developer.associated-domains",
                "com.apple.security.application-groups",
                "keychain-access-groups",
                "com.apple.security.app-sandbox",
                "com.example.alpha",
                "com.example.zeta"
            ]

            let actual = Entitlements(dictionary: dictionary, source: .codeSignature).entries.map(\.key)

            #expect(actual == expected)
        }

        @Test("A property list's true and false are switches; a number is not")
        func booleansAndNumbers() {
            let dictionary: [String: Any] = ["on": true, "off": false, "number": NSNumber(value: 1)]
            let expected = [
                Entitlement(key: "number", value: .list(["1"])),
                Entitlement(key: "off", value: .boolean(false)),
                Entitlement(key: "on", value: .boolean(true))
            ]

            let actual = Entitlements(dictionary: dictionary, source: .codeSignature).entries

            #expect(actual == expected)
        }

        @Test("An array's items are kept in order; a dictionary's entries are listed by key; a string is one item")
        func lists() {
            let dictionary: [String: Any] = [
                "array": ["b", "a", true],
                "dictionary": ["z": "last", "a": 1] as [String: Any],
                "string": "development"
            ]
            let expected = [
                Entitlement(key: "array", value: .list(["b", "a", "Yes"])),
                Entitlement(key: "dictionary", value: .list(["a = 1", "z = last"])),
                Entitlement(key: "string", value: .list(["development"]))
            ]

            let actual = Entitlements(dictionary: dictionary, source: .executable).entries

            #expect(actual == expected)
        }

        @Test("No entitlements make an empty list")
        func empty() {
            let actual = Entitlements(dictionary: [:], source: .codeSignature)

            #expect(actual.entries.isEmpty)
        }

        @Test("An entitlement's text is Yes or No for a switch, and its items joined by commas for a list")
        func text() {
            let domains = Entitlement(key: "com.apple.developer.associated-domains", value: .list(["applinks:a.com", "applinks:b.com"]))
            let empty = Entitlement(key: "keychain-access-groups", value: .list([]))

            #expect(Entitlement(key: "get-task-allow", value: .boolean(true)).text == "Yes")
            #expect(Entitlement(key: "get-task-allow", value: .boolean(false)).text == "No")
            #expect(domains.text == "applinks:a.com, applinks:b.com")
            #expect(empty.text == "")
        }
    }
#endif
