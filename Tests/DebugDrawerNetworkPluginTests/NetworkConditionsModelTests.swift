#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NetworkConditionsModelTests {
        @Test("Each change is saved: a new model over the same storage loads the profiles, their order and switches")
        func persistsAcrossLaunches() {
            let storage = FakeNetworkConditionStorage()
            let first = NetworkConditionProfile(name: "First", host: .exact("a.test"), latency: .milliseconds(100))
            let second = NetworkConditionProfile(name: "Second", bandwidth: 5000, failureRate: 20, failure: .internalServerError)
            let sut = NetworkConditionsModel(
                storage: storage, active: NetworkConditions(),
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            sut.save(first)
            sut.save(second)
            sut.setEnabled(false, id: first.id)
            sut.move(second.id, by: -1)
            let relaunched = NetworkConditionsModel(
                storage: storage, active: NetworkConditions(),
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )

            relaunched.load()

            var expectedFirst = first
            expectedFirst.isEnabled = false
            #expect(relaunched.profiles == [second, expectedFirst])
            #expect(relaunched.issue == nil)
        }

        @Test("Each change reaches the active profiles: on, off, edited and deleted")
        func changesReachActiveProfiles() throws {
            let active = NetworkConditions()
            let sut = NetworkConditionsModel(
                storage: FakeNetworkConditionStorage(), active: active,
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            var profile = NetworkConditionProfile(name: "Slow", host: .exact("api.test"), latency: .seconds(2))
            let url = try #require(URL(string: "https://api.test/"))

            sut.save(profile)
            let afterSave = active.plan(for: url)?.effect.latency
            sut.setEnabled(false, id: profile.id)
            let afterOff = active.plan(for: url)
            sut.setEnabled(true, id: profile.id)
            profile.latency = .seconds(3)
            sut.save(profile)
            let afterEdit = active.plan(for: url)?.effect.latency
            sut.delete(profile.id)
            let afterDelete = active.plan(for: url)

            #expect(afterSave == .seconds(2))
            #expect(afterOff == nil)
            #expect(afterEdit == .seconds(3))
            #expect(afterDelete == nil)
            #expect(sut.profiles.isEmpty)
        }

        @Test("Profiles passed in at install are added once, by id: a saved profile of the same id wins")
        func loadAdding() {
            let storage = FakeNetworkConditionStorage()
            let seeded = NetworkConditionProfile(name: "Seeded", latency: .seconds(2))
            let first = NetworkConditionsModel(
                storage: storage, active: NetworkConditions(),
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            first.load(adding: [seeded])
            first.setEnabled(false, id: seeded.id)
            let second = NetworkConditionsModel(
                storage: storage, active: NetworkConditions(),
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )

            second.load(adding: [seeded])

            #expect(second.profiles.count == 1)
            #expect(second.profiles.first?.isEnabled == false)
        }

        @Test("Moving a profile earlier makes it apply first; a move past either end stops there")
        func reorder() throws {
            let active = NetworkConditions()
            let sut = NetworkConditionsModel(
                storage: FakeNetworkConditionStorage(), active: active,
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            let first = NetworkConditionProfile(name: "First")
            let second = NetworkConditionProfile(name: "Second")
            let url = try #require(URL(string: "https://api.test/"))
            sut.save(first)
            sut.save(second)

            sut.move(second.id, by: -5)
            let afterTop = sut.profiles.map(\.name)
            sut.move(second.id, by: 9)
            let afterBottom = sut.profiles.map(\.name)
            let actual = active.plan(for: url)?.effect.profileName

            #expect(afterTop == ["Second", "First"])
            #expect(afterBottom == ["First", "Second"])
            #expect(actual == "First")
        }

        @Test("The indicator names the one profile on, counts several, and says nothing while none is")
        func activeSummary() {
            let threeG = NetworkConditionProfile(name: "3G")
            let lossy = NetworkConditionProfile(name: "Lossy")
            let off = NetworkConditionProfile(name: "Off", isEnabled: false)

            #expect([threeG, off].activeSummary == "3G active")
            #expect([threeG, lossy, off].activeSummary == "2 conditions active")
            #expect([off].activeSummary == nil)
            #expect([NetworkConditionProfile]().activeSummary == nil)
        }

        @Test("The header's short label counts the profiles on, never naming them, and says nothing while none is")
        func activeCountLabel() {
            let slow = NetworkConditionProfile(name: "A profile with a long name that no header has room for")
            let lossy = NetworkConditionProfile(name: "Lossy")
            let off = NetworkConditionProfile(name: "Off", isEnabled: false)

            #expect([slow, off].activeCountLabel == "1 active")
            #expect([slow, lossy, off].activeCountLabel == "2 active")
            #expect([off].activeCountLabel == nil)
            #expect([NetworkConditionProfile]().activeCountLabel == nil)
        }

        @Test("A saved file in a later format loads nothing and says so; an unreadable one too")
        func unreadableFiles() {
            let later = FakeNetworkConditionStorage(profiles: Data(#"{"version":2,"profiles":[]}"#.utf8))
            let garbage = FakeNetworkConditionStorage(profiles: Data("not json".utf8))
            let sutLater = NetworkConditionsModel(
                storage: later, active: NetworkConditions(),
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            let sutGarbage = NetworkConditionsModel(
                storage: garbage, active: NetworkConditions(),
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )

            sutLater.load()
            sutGarbage.load()

            #expect(sutLater.issue == .unsupportedVersion(2))
            #expect(sutLater.profiles.isEmpty)
            #expect(sutGarbage.issue == .unreadable)
            #expect(NetworkMocksIssue.unsupportedVersion(2).message(about: "conditions")
                == "The saved conditions are in format 2, newer than this build reads, so none are loaded.")
        }

        @Test("A change that can't be saved still applies, and says it lasts until the app quits; the next saved change clears that")
        func notSaved() throws {
            let storage = FakeNetworkConditionStorage()
            let active = NetworkConditions()
            let sut = NetworkConditionsModel(
                storage: storage, active: active,
                scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
            )
            let profile = NetworkConditionProfile(name: "Slow", latency: .seconds(1))
            let url = try #require(URL(string: "https://api.test/"))
            storage.failsWriting = true

            sut.save(profile)
            let issueWhileFailing = sut.issue
            let applied = active.plan(for: url) != nil
            storage.failsWriting = false
            sut.setEnabled(false, id: profile.id)

            #expect(issueWhileFailing == .notSaved)
            #expect(applied)
            #expect(sut.issue == nil)
        }
    }
#endif
