#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkConditionsTests {
        @Test(
            "A profile's host is matched as a mock rule's is: exactly without regard to case, by a wildcard or a regex, or every host",
            arguments: [
                (NetworkMockRule.Pattern.exact("api.example.com"), "https://API.example.com/v1", true),
                (.exact("api.example.com"), "https://cdn.example.com/v1", false),
                (.wildcard("*.example.com"), "https://img.example.com/a.png", true),
                (.wildcard("*.example.com"), "https://a.b.example.com/", false),
                (.wildcard("**.example.com"), "https://a.b.example.com/", true),
                (.regex(#"api\d\.example\.com"#), "https://api2.example.com/", true),
                (.regex(#"api\d\.example\.com"#), "https://api2.example.com.evil.test/", false),
                (.any, "http://127.0.0.1:8080/", true)
            ]
        )
        func hostMatching(host: NetworkMockRule.Pattern, address: String, expected: Bool) throws {
            let sut = NetworkConditions()
            sut.activate([NetworkConditionProfile(name: "Slow", host: host, latency: .seconds(1))],
                         scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0))
            let url = try #require(URL(string: address))

            let actual = sut.plan(for: url) != nil

            #expect(actual == expected)
        }

        @Test("The first enabled profile that matches applies; a disabled one and one whose regex doesn't compile are skipped")
        func firstEnabledMatchWins() throws {
            let sut = NetworkConditions()
            let profiles = [
                NetworkConditionProfile(name: "Off", isEnabled: false, host: .exact("api.example.com"), latency: .seconds(9)),
                NetworkConditionProfile(name: "Broken", host: .regex("api(.example.com"), latency: .seconds(8)),
                NetworkConditionProfile(name: "API", host: .exact("api.example.com"), latency: .seconds(2)),
                NetworkConditionProfile(name: "Everything", latency: .seconds(1))
            ]
            sut.activate(profiles, scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0))
            let api = try #require(URL(string: "https://api.example.com/"))
            let other = try #require(URL(string: "https://other.example.com/"))

            let actualAPI = sut.plan(for: api)?.effect
            let actualOther = sut.plan(for: other)?.effect.profileName

            #expect(actualAPI?.profileName == "API")
            #expect(actualAPI?.latency == .seconds(2))
            #expect(actualOther == "Everything")
        }

        @Test("With no profile on, no request is conditioned")
        func noProfiles() throws {
            let sut = NetworkConditions()
            sut.activate([NetworkConditionProfile(name: "Off", isEnabled: false)],
                         scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0))
            let url = try #require(URL(string: "https://api.example.com/"))

            let actual = sut.plan(for: url)

            #expect(actual == nil)
        }

        @Test(
            "A request fails when the roll is below the failure rate: 0% never, 100% always, 30% on a roll of 29 but not 30",
            arguments: [(0, 0, false), (100, 99, true), (30, 29, true), (30, 30, false), (150, 99, true), (-5, 0, false)]
        )
        func failureRate(rate: Int, roll: Int, expectedFails: Bool) throws {
            let sut = NetworkConditions()
            sut.activate([NetworkConditionProfile(name: "Lossy", failureRate: rate, failure: .notConnectedToInternet)],
                         scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(roll))
            let url = try #require(URL(string: "https://api.example.com/"))
            let expected: NetworkConditionProfile.Failure? = expectedFails ? .notConnectedToInternet : nil

            let actual = try #require(sut.plan(for: url)).effect.failure

            #expect(actual == expected)
        }

        @Test("Each request rolls afresh: with rolls of 10 then 90 at 50%, the first fails and the second doesn't")
        func rollsPerRequest() throws {
            let sut = NetworkConditions()
            sut.activate([NetworkConditionProfile(name: "Lossy", failureRate: 50, failure: .timedOut)],
                         scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(10, 90))
            let url = try #require(URL(string: "https://api.example.com/"))

            let first = sut.plan(for: url)?.effect.failure
            let second = sut.plan(for: url)?.effect.failure

            #expect(first == .timedOut)
            #expect(second == nil)
        }

        @Test("A negative latency is none, a cap of zero is no cap, and a failed request has no cap")
        func effectBoundaries() throws {
            let sut = NetworkConditions()
            let profiles = [
                NetworkConditionProfile(name: "Odd", host: .exact("odd.test"), latency: .milliseconds(-50), bandwidth: 0),
                NetworkConditionProfile(name: "Down", host: .exact("down.test"), bandwidth: 1000, failureRate: 100, failure: .internalServerError)
            ]
            sut.activate(profiles, scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0))
            let odd = try #require(URL(string: "https://odd.test/"))
            let down = try #require(URL(string: "https://down.test/"))

            let actualOdd = try #require(sut.plan(for: odd)).effect
            let actualDown = try #require(sut.plan(for: down)).effect

            #expect(actualOdd.latency == .zero)
            #expect(actualOdd.bandwidth == nil)
            #expect(actualDown.bandwidth == nil)
            #expect(actualDown.failure == .internalServerError)
        }

        @Test("The log's summary of an effect names each thing the profile did")
        func effectSummary() {
            let slow = NetworkConditionEffect(profileName: "3G", latency: .milliseconds(2000), bandwidth: 97500, failure: nil)
            let down = NetworkConditionEffect(profileName: "Down", latency: .milliseconds(300), bandwidth: nil, failure: .timedOut)
            let none = NetworkConditionEffect(profileName: "Nothing", latency: .zero, bandwidth: nil, failure: nil)

            #expect(slow.summary == "Delayed 2,000 ms · Capped at 97.5 KB/s")
            #expect(down.summary == "Delayed 300 ms · Failed: timeout")
            #expect(none.summary == "No effect")
        }
    }
#endif
