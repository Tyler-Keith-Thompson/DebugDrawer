import DebugDrawerAnalytics
import Testing

@Suite
struct AnalyticsRedactionTests {
    @Test("The standard rules mask keys holding email, phone, token, secret, password, session, auth and API key, ignoring case, at any depth")
    func standardKeys() {
        let sut = AnalyticsRedaction.standard
        let mask = AnalyticsValue.string(AnalyticsRedaction.mask)
        let properties: [String: AnalyticsValue] = [
            "Email": "a", "phone_number": "b", "refresh_token": "c", "client_secret": "d", "Password": "e",
            "session_id": "f", "authorization": "g", "apiKey": "h", "api_key": "i", "x-api-key": "j",
            "plan": "pro", "seats": 3,
            "user": ["contact_email": "k", "country": "NZ"],
            "items": [["sku": "1", "token": "l"]]
        ]
        let expected: [String: AnalyticsValue] = [
            "Email": mask, "phone_number": mask, "refresh_token": mask, "client_secret": mask, "Password": mask,
            "session_id": mask, "authorization": mask, "apiKey": mask, "api_key": mask, "x-api-key": mask,
            "plan": "pro", "seats": 3,
            "user": ["contact_email": mask, "country": "NZ"],
            "items": [["sku": "1", "token": mask]]
        ]

        let actual = sut.redacting(properties)

        #expect(actual == expected)
    }

    @Test("The standard rules mask a string holding an email address or a JSON Web Token under any key, and leave other values")
    func standardValues() {
        let sut = AnalyticsRedaction.standard
        let mask = AnalyticsValue.string(AnalyticsRedaction.mask)
        let properties: [String: AnalyticsValue] = [
            "note": "write to Someone@Example.COM soon",
            "header": "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc-DEF_123",
            "tags": ["ok", "x@y.io"],
            "at": "@handle",
            "count": 2, "ratio": 0.5, "flag": true, "nothing": nil
        ]
        let expected: [String: AnalyticsValue] = [
            "note": mask, "header": mask, "tags": ["ok", mask], "at": "@handle",
            "count": 2, "ratio": 0.5, "flag": true, "nothing": nil
        ]

        let actual = sut.redacting(properties)

        #expect(actual == expected)
    }

    @Test("A host's rules add to the standard ones: its keys and value patterns mask too, and the standard ones still do")
    func hostRulesAdd() {
        let sut = AnalyticsRedaction.standard.adding(keys: ["Customer_Name"], values: [#"\bACCT-\d{6}\b"#])
        let mask = AnalyticsValue.string(AnalyticsRedaction.mask)
        let properties: [String: AnalyticsValue] = [
            "customer_name": "Ada", "reference": "for acct-123456 today", "short": "ACCT-12", "email": "a@b.co"
        ]
        let expected: [String: AnalyticsValue] = ["customer_name": mask, "reference": mask, "short": "ACCT-12", "email": mask]

        let actual = sut.redacting(properties)

        #expect(actual == expected)
        #expect(sut.keyPatterns.isSuperset(of: AnalyticsRedaction.standard.keyPatterns.union(["customer_name"])))
        #expect(sut.valuePatterns.isSuperset(of: AnalyticsRedaction.standard.valuePatterns))
    }

    @Test("No rules mask nothing; an empty key pattern is ignored; rules are equal by their patterns")
    func noneAndEquality() {
        let properties: [String: AnalyticsValue] = ["password": "p", "note": "a@b.co"]

        let actual = AnalyticsRedaction.none.redacting(properties)

        #expect(actual == properties)
        #expect(AnalyticsRedaction(keys: [""]) == AnalyticsRedaction.none)
        #expect(AnalyticsRedaction(keys: ["A"], values: ["x"]) == AnalyticsRedaction(keys: ["a"], values: ["x"]))
        #expect(AnalyticsRedaction(values: ["x"]) != AnalyticsRedaction(values: ["y"]))
        #expect(!AnalyticsRedaction.none.masksKey("password"))
        #expect(!AnalyticsRedaction.none.masksValue("a@b.co"))
    }
}
