@testable import DebugDrawerReceiver
import Testing

// How free text's `key=value` and `key: value` pairs are read and masked, the one reading the
// drawer's rules and the diagnostics capture's share. The key test here is a plain closure; each
// rules type's own tests pin its key patterns and their case.
@Suite
struct KeyValuePairsTests {
    @Test("Each key=value pair whose key the test accepts has its value masked up to whitespace; the rest stays", arguments: [
        ("order=1042 token=abc user=7", "order=1042 token=[REDACTED] user=7"),
        ("token=a token=b token=c", "token=[REDACTED] token=[REDACTED] token=[REDACTED]"),
        ("x-api-token=1 user.token=2 refresh_token=3", "x-api-token=[REDACTED] user.token=[REDACTED] refresh_token=[REDACTED]"),
        ("token = abc", "token = [REDACTED]"),
        ("note=token=abc", "note=token=[REDACTED]")
    ])
    func equalsPairs(text: String, expected: String) {
        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == expected)
    }

    @Test("A key: value pair is masked like key=value, with spaces around the colon allowed", arguments: [
        ("Refreshing, token: abc, retrying", "Refreshing, token: [REDACTED], retrying"),
        ("token : abc", "token : [REDACTED]"),
        ("token:\tabc", "token:\t[REDACTED]")
    ])
    func colonPairs(text: String, expected: String) {
        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == expected)
    }

    @Test("Each item of a URL's query string is read on its own; the scheme's :// isn't a separator")
    func queryString() {
        let text = "GET https://api.example.com/v1/feed?page=2&access_token=abc123&lang=en failed"
        let expected = "GET https://api.example.com/v1/feed?page=2&access_token=[REDACTED]&lang=en failed"

        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == expected)
    }

    @Test("JSON-style quoted keys and values: the value is masked inside its quotes, escapes and spaces included", arguments: [
        (#"{"token": "abc def", "user": "7"}"#, #"{"token": "[REDACTED]", "user": "7"}"#),
        (#"{"password": "a\"b c"}"#, #"{"password": "[REDACTED]"}"#),
        ("{'token': 'abc'}", "{'token': '[REDACTED]'}"),
        (#""access token" = abc"#, #""access token" = [REDACTED]"#),
        (#"sent {"token":"abc","n":1}"#, #"sent {"token":"[REDACTED]","n":1}"#)
    ])
    func quoted(text: String, expected: String) {
        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") || $0.contains("password") }

        #expect(actual == expected)
    }

    @Test("A quoted value with no closing quote is masked to the end of its line")
    func unterminatedQuote() {
        let text = "token: \"abc def\nnext line"
        let expected = "token: \"[REDACTED]\nnext line"

        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == expected)
    }

    @Test("An unquoted value ends at & , ; ) ] } or a quote", arguments: [
        ("token=abc;rest", "token=[REDACTED];rest"),
        ("(token=abc)", "(token=[REDACTED])"),
        ("[token=abc]", "[token=[REDACTED]]"),
        ("{token: abc}", "{token: [REDACTED]}"),
        ("token=abc,user=7", "token=[REDACTED],user=7"),
        (#"say "token=abc" twice"#, #"say "token=[REDACTED]" twice"#)
    ])
    func valueEnds(text: String, expected: String) {
        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == expected)
    }

    @Test("A value starting with a bracket is left for the pairs inside it")
    func bracketedValue() {
        let text = #"token: {"password": "x", "id": 1}"#
        let expected = #"token: {"password": "[REDACTED]", "id": 1}"#

        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") || $0.contains("password") }

        #expect(actual == expected)
    }

    @Test("Text with no pair to mask comes back unchanged", arguments: [
        "",
        "nothing to see here",
        "token",
        "token=",
        "token=, user=7",
        "a == token",
        "Foo::token is a member",
        "open mytoken://callback/path",
        "12:30:45 token expired",
        "user=7 order=1042"
    ])
    func unchanged(text: String) {
        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == text)
    }

    @Test("Characters outside ASCII are kept whole around a masked value, and may be part of a key")
    func nonASCII() {
        let text = "café token=naïve après contraseña: ñandú 🎉"
        let expected = "café token=[REDACTED] après contraseña: [REDACTED] 🎉"

        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") || $0.contains("contraseña") }

        #expect(actual == expected)
    }

    @Test("Pairs on every line of a text of many lines are masked")
    func manyLines() {
        let text = "a=1 token=x\r\nb: 2\ntoken: \"y\"\n"
        let expected = "a=1 token=[REDACTED]\r\nb: 2\ntoken: \"[REDACTED]\"\n"

        let actual = text.maskingKeyValuePairs(with: "[REDACTED]") { $0.contains("token") }

        #expect(actual == expected)
    }

    @Test("The key test is asked with the key alone, as written")
    func keysAsked() {
        final class Asked {
            var keys: [String] = []
        }
        let asked = Asked()
        let text = #"Order=1 "Access Token": x y-z : 2 note"#
        let expected = ["Order", "Access Token", "y-z"]

        _ = text.maskingKeyValuePairs(with: "[REDACTED]") { key in
            asked.keys.append(key)
            return false
        }

        #expect(asked.keys == expected)
    }
}
