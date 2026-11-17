#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite
    struct NetworkConditionDraftTests {
        @Test("A profile's draft gives the same profile back: the bandwidth in KB/s and the latency in ms")
        func roundTrip() throws {
            let expected = NetworkConditionProfile(
                name: "3G", host: .wildcard("*.example.com"), latency: .milliseconds(100), bandwidth: 97500,
                failureRate: 5, failure: .notConnectedToInternet
            )

            let sut = NetworkConditionDraft(expected, isNew: false)
            let actual = try #require(sut.profile)

            #expect(sut.bandwidth == "97.5")
            #expect(sut.latency == "100")
            #expect(actual == expected)
        }

        @Test("An empty bandwidth is no cap; an empty name is the hosts and the effect")
        func emptyFields() throws {
            var sut = NetworkConditionDraft.new()
            sut.latency = "2000"

            let actual = try #require(sut.profile)

            #expect(actual.bandwidth == nil)
            #expect(actual.name == "All hosts 2,000 ms")
        }

        @Test(
            "Each number out of range says why and holds Save back",
            arguments: [
                ("latency", "-1"), ("latency", "soon"), ("bandwidth", "0"), ("bandwidth", "fast"),
                ("failureRate", "101"), ("failureRate", "-1"), ("failureRate", "ten")
            ]
        )
        func problems(field: String, text: String) {
            var sut = NetworkConditionDraft.new()
            switch field {
            case "latency": sut.latency = text
            case "bandwidth": sut.bandwidth = text
            default: sut.failureRate = text
            }

            let problems = [sut.latencyProblem, sut.bandwidthProblem, sut.failureRateProblem].compactMap(\.self)

            #expect(problems.count == 1)
            #expect(sut.profile == nil)
        }

        @Test("The boundaries are accepted: no latency, 100% failure, a cap of one byte a second")
        func boundaries() throws {
            var sut = NetworkConditionDraft.new()
            sut.latency = "0"
            sut.failureRate = "100"
            sut.bandwidth = "0.001"

            let actual = try #require(sut.profile)

            #expect(actual.latency == .zero)
            #expect(actual.failureRate == 100)
            #expect(actual.bandwidth == 1)
        }

        @Test("An invalid host regex says why and holds Save back; an empty exact host asks for one")
        func hostProblems() {
            var regex = NetworkConditionDraft.new()
            regex.hostKind = .regex
            regex.host = "api(.example"
            var empty = NetworkConditionDraft.new()
            empty.hostKind = .exact

            #expect(regex.hostProblem?.hasPrefix("Not a valid regular expression") == true)
            #expect(regex.profile == nil)
            #expect(empty.hostProblem == "Enter a host, or match any.")
        }

        @Test("A preset fills the effect, and the name only while it is empty")
        func preset() throws {
            let edge = try #require(NetworkConditionPreset.all.first { $0.name == "Edge" })
            var unnamed = NetworkConditionDraft.new()
            var named = NetworkConditionDraft.new()
            named.name = "Checkout"

            unnamed.apply(edge)
            named.apply(edge)

            #expect(unnamed.name == "Edge")
            #expect(named.name == "Checkout")
            #expect(unnamed.latency == "400")
            #expect(unnamed.bandwidth == "30")
            #expect(unnamed.failureRate == "0")
            #expect(NetworkConditionPreset.all.map(\.name) == ["3G", "Edge", "Lossy"])
        }
    }
#endif
