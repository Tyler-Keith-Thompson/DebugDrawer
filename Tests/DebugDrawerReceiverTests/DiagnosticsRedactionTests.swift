@testable import DebugDrawerReceiver
import Foundation
import Testing

// The capture's redaction rules on each kind of text it keeps: log text, key/value fields,
// headers, URLs and JSON bodies, with the standard rules, added ones and none.
@Suite
struct DiagnosticsRedactionTests {
    @Test("Standard rules mask an email address, a JWT, a bearer credential and a named secret inside log text, keeping the rest")
    func standardMasksSecretsInText() {
        let sut = DebugDrawerDiagnosticsRedaction.standard
        let text = "jane@example.com sent eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl with Bearer abc.def-123 and token: s3cr3t, then left"
        let expected = "[REDACTED] sent [REDACTED] with [REDACTED] and [REDACTED], then left"

        let actual = sut.redacting(text: text)

        #expect(actual == expected)
    }

    @Test("Log text has the value of each key=value and key: value pair whose key contains a key pattern masked, before the value patterns run")
    func keyValuePairsInText() {
        let sut = DebugDrawerDiagnosticsRedaction.standard.adding(keys: ["customer"])
        let text = #"Checkout customer_id=C-77 session: 9f2 phone=555-0100 cart=3 {"refresh_token": "r 1"}"#
        let expected = #"Checkout customer_id=[REDACTED] session: [REDACTED] phone=[REDACTED] cart=3 {"refresh_token": "[REDACTED]"}"#

        let actual = sut.redacting(text: text)

        #expect(actual == expected)
    }

    @Test("With no rules, log text with key=value pairs comes back unchanged")
    func keyValuePairsNoRules() {
        let sut = DebugDrawerDiagnosticsRedaction.none
        let text = "token=abc session: 9f2"

        let actual = sut.redacting(text: text)

        #expect(actual == text)
    }

    @Test("A field under a sensitive key is masked whole; others have value patterns masked")
    func fieldsMaskedByKey() {
        let sut = DebugDrawerDiagnosticsRedaction.standard
        let fields = ["userPassword": "hunter2", "Session-ID": "42", "contact": "write to jane@example.com", "screen": "cart"]
        let expected = ["userPassword": "[REDACTED]", "Session-ID": "[REDACTED]", "contact": "write to [REDACTED]", "screen": "cart"]

        let actual = sut.redacting(fields: fields)

        #expect(actual == expected)
    }

    @Test("Listed headers and headers named after a key pattern are masked, ignoring case")
    func headersMasked() {
        let sut = DebugDrawerDiagnosticsRedaction.standard.adding(headers: ["X-Customer"])
        let headers = ["authorization": "Basic Zm9vOmJhcg==", "COOKIE": "a=b", "X-Api-Key": "k", "x-customer": "Jane", "Accept": "application/json"]
        let expected = [
            "authorization": "[REDACTED]", "COOKIE": "[REDACTED]", "X-Api-Key": "[REDACTED]", "x-customer": "[REDACTED]", "Accept": "application/json"
        ]

        let actual = sut.redacting(headers: headers)

        #expect(actual == expected)
    }

    @Test("A URL's user, password and sensitive query items are masked, and an email in its path and fragment, never the host")
    func urlMasked() throws {
        let sut = DebugDrawerDiagnosticsRedaction.standard
        let url = try #require(URL(string: "https://jane:pw@api.example.com/users/jane@example.com/orders?auth_token=abc&page=2#to:jane@example.com"))
        let expected = "https://[REDACTED]:[REDACTED]@api.example.com/users/[REDACTED]/orders?auth_token=[REDACTED]&page=2#to:[REDACTED]"

        let actual = sut.redacting(url: url)

        #expect(actual == expected)
    }

    @Test("A JSON body has sensitive keys, JSON paths and value patterns masked at any depth, through arrays, and its other values kept")
    func jsonMasked() throws {
        let sut = DebugDrawerDiagnosticsRedaction.standard.adding(jsonPaths: ["order.items.sku", "*.note"])
        let body = Data(
            #"{"order":{"items":[{"sku":"A1","qty":2}],"note":"for jane@example.com"},"refreshToken":"r","count":3,"ok":true,"gift":null}"#.utf8
        )
        let expected =
            #"{"count":3,"gift":null,"ok":true,"order":{"items":[{"qty":2,"sku":"[REDACTED]"}],"note":"[REDACTED]"},"refreshToken":"[REDACTED]"}"#

        let actual = try #require(sut.redacting(json: body))

        #expect(String(bytes: actual, encoding: .utf8) == expected)
    }

    @Test("A body that isn't JSON has no redacted form")
    func nonJSONHasNoRedactedForm() {
        let sut = DebugDrawerDiagnosticsRedaction.none

        let actual = sut.redacting(json: Data("password=hunter2".utf8))

        #expect(actual == nil)
    }

    @Test("No rules mask nothing")
    func noneMasksNothing() {
        let sut = DebugDrawerDiagnosticsRedaction.none
        let text = "jane@example.com password=hunter2"

        let actual = sut.redacting(text: text)

        #expect(actual == text)
    }

    @Test("Added value patterns mask their matches beside the standard ones; rules compare by their patterns")
    func addedValuePatterns() {
        let sut = DebugDrawerDiagnosticsRedaction.standard.adding(keys: ["Customer"], values: [#"\bACCT-\d{6}\b"#])
        let expectedKeys = DebugDrawerDiagnosticsRedaction.standard.keyPatterns.union(["customer"])

        let actual = sut.redacting(text: "account ACCT-123456 of jane@example.com")

        #expect(actual == "account [REDACTED] of [REDACTED]")
        #expect(sut.keyPatterns == expectedKeys)
        #expect(sut == DebugDrawerDiagnosticsRedaction.standard.adding(keys: ["customer"], values: [#"\bACCT-\d{6}\b"#]))
        #expect(sut != DebugDrawerDiagnosticsRedaction.standard)
    }
}
