#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. Its
    // defaults are a hand-written in-memory store; nothing touches UserDefaults. Every command
    // lands before `send` returns, so the tests read the snapshot right after sending.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsModelTests {
        @Test("A snapshot holding every kind of value, other domains' keys and the filters encodes to JSON and decodes equal")
        func snapshotRoundTrips() throws {
            let storage = FakeUserDefaultsStorage(
                suites: [.named("group.shared"): [
                    "name": .string("Ada"),
                    "launchCount": .number(NSNumber(value: 3)),
                    "huge": .number(NSNumber(value: UInt64.max)),
                    "volume": .number(NSNumber(value: 2.5)),
                    "limit": .number(NSNumber(value: Double.infinity)),
                    "sync": .bool(true),
                    "lastLaunch": .date(Date(timeIntervalSinceReferenceDate: 820_000_000.5)),
                    "token": .data(Data([0xDE, 0xAD, 0xBE, 0xEF])),
                    "tabs": .array([.string("recent"), .number(NSNumber(value: 1))]),
                    "settings": .dictionary(["theme": .dictionary(["accent": .string("teal")]), "on": .bool(false)])
                ]],
                otherDomains: [.registration: ["fallback": .number(NSNumber(value: 7))]]
            )
            let transport = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage))
            transport.send(UserDefaultsCommand(.selectSuite(.named("group.shared"))))
            transport.send(UserDefaultsCommand(.setShowOtherDomains(true)))
            transport.send(UserDefaultsCommand(.setSearchText("a")))
            let expected = transport.snapshot

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(UserDefaultsSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.entries.count == 11)
            #expect(actual.selectedSuite == .named("group.shared"))
            #expect(actual.suites == [.standard, .named("group.shared")])
            #expect(actual.searchText == "a")
            #expect(actual.showOtherDomains)
            #expect(actual.entries.first { $0.key == "fallback" }?.domain == .registration)
        }

        @Test("A snapshot before anything is read encodes to JSON and decodes equal, with no keys")
        func unreadSnapshotRoundTrips() throws {
            let sut = UserDefaultsModel(suites: [], storage: FakeUserDefaultsStorage(suites: [.standard: ["a": .string("b")]]))
            let expected = UserDefaultsSnapshot()

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(UserDefaultsSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.entries.isEmpty)
        }

        @Test(
            "Each kind of value encodes to JSON and decodes as the same kind and value",
            arguments: [
                PropertyListValue.string("Ada"),
                .number(NSNumber(value: -42)),
                .number(NSNumber(value: UInt64.max)),
                .number(NSNumber(value: 2.5)),
                .number(NSNumber(value: -Double.infinity)),
                .bool(false),
                .date(Date(timeIntervalSince1970: 1_800_000_000.25)),
                .data(Data([0, 1, 2, 255])),
                .array([.string("a"), .array([.bool(true)])]),
                .dictionary(["inner": .dictionary(["n": .number(NSNumber(value: 1))]), "empty": .array([])])
            ]
        )
        func valueRoundTrips(expected: PropertyListValue) throws {
            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(PropertyListValue.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.type == expected.type)
            if case let .number(expectedNumber) = expected, case let .number(actualNumber) = actual {
                #expect(CFNumberIsFloatType(actualNumber as CFNumber) == CFNumberIsFloatType(expectedNumber as CFNumber))
                #expect(actualNumber.stringValue == expectedNumber.stringValue)
            }
        }

        @Test("An integer encodes under integer, a real under real, and a real that isn't finite as its description")
        func numberEncoding() throws {
            let integer = try String(bytes: JSONEncoder().encode(PropertyListValue.number(NSNumber(value: 3))), encoding: .utf8)
            let real = try String(bytes: JSONEncoder().encode(PropertyListValue.number(NSNumber(value: 3.0))), encoding: .utf8)
            let notANumber = try String(bytes: JSONEncoder().encode(PropertyListValue.number(NSNumber(value: Double.nan))), encoding: .utf8)

            let decoded = try JSONDecoder().decode(PropertyListValue.self, from: Data((notANumber ?? "").utf8))

            #expect(integer == #"{"integer":3}"#)
            #expect(real == #"{"real":3}"#)
            #expect(notANumber == #"{"real":"nan"}"#)
            guard case let .number(number) = decoded else {
                Issue.record("Decoded \(decoded), not a number")
                return
            }
            #expect(number.doubleValue.isNaN)
        }

        @Test("A value naming no kind, or two, doesn't decode")
        func malformedValue() {
            let empty = Data("{}".utf8)
            let two = Data(#"{"string":"a","bool":true}"#.utf8)

            #expect(throws: DecodingError.self) { try JSONDecoder().decode(PropertyListValue.self, from: empty) }
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(PropertyListValue.self, from: two) }
        }

        @Test("Every command encodes to JSON and decodes equal, and drives the model through a direct transport")
        func commandsRoundTrip() throws {
            let storage = FakeUserDefaultsStorage(suites: [.named("group.shared"): ["old": .string("x")]])
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage, now: { now }))
            let commands: [UserDefaultsCommand.Action] = [
                .startObserving,
                .selectSuite(.named("group.shared")),
                .setShowOtherDomains(true),
                .setSearchText("e"),
                .set(.dictionary(["a": .array([.data(Data([1]))])]), forKey: "settings"),
                .add("created", type: .date),
                .remove("old"),
                .reload,
                .stopObserving
            ]
            let expectedEntries = [
                DefaultsEntry(key: "created", value: .date(now)),
                DefaultsEntry(key: "settings", value: .dictionary(["a": .array([.data(Data([1]))])]))
            ]

            var decoded: [UserDefaultsCommand.Action] = []
            for command in commands {
                let roundTripped = try JSONDecoder().decode(UserDefaultsCommand.self, from: JSONEncoder().encode(UserDefaultsCommand(command)))
                decoded.append(roundTripped.action)
                sut.send(roundTripped)
            }

            #expect(decoded == commands)
            #expect(sut.snapshot.entries == expectedEntries)
            #expect(sut.snapshot.searchText == "e")
            #expect(sut.snapshot.showOtherDomains)
            #expect(sut.snapshot.selectedSuite == .named("group.shared"))
            #expect(storage.observerCount == 0)
        }

        @Test("Keys list sorted, Standard's first, and a repeated or empty suite name is offered once or not at all")
        func listingAndSorting() {
            let storage = FakeUserDefaultsStorage(suites: [.standard: [
                "zeta": .string("z"), "Alpha": .string("a"), "beta": .bool(true), "123": .number(1)
            ]])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.a", "", "group.b", "group.a"], storage: storage))
            let expectedSuites: [UserDefaultsSuite] = [.standard, .named("group.a"), .named("group.b")]

            sut.send(UserDefaultsCommand(.reload))

            #expect(sut.snapshot.suites == expectedSuites)
            #expect(sut.snapshot.entries.map(\.key) == ["123", "Alpha", "beta", "zeta"])
            #expect(sut.snapshot.persistentKeys == ["123", "Alpha", "beta", "zeta"])
        }

        @Test("Other domains' keys hide unless shown, and the search matches a key or a value without regard to case")
        func filters() {
            let storage = FakeUserDefaultsStorage(
                suites: [.standard: ["launchCount": .number(3), "username": .string("Ada")]],
                otherDomains: [.global: ["NSLanguages": .array([.string("en")])]]
            )
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.reload))
            let hidden = sut.snapshot.filteredEntries.map(\.key)
            sut.send(UserDefaultsCommand(.setShowOtherDomains(true)))
            let shown = sut.snapshot.filteredEntries.map(\.key)
            sut.send(UserDefaultsCommand(.setShowOtherDomains(false)))
            sut.send(UserDefaultsCommand(.setSearchText("ADA")))
            let byValue = sut.snapshot.filteredEntries.map(\.key)

            sut.send(UserDefaultsCommand(.setSearchText("launch")))

            #expect(hidden == ["launchCount", "username"])
            #expect(shown == ["NSLanguages", "launchCount", "username"])
            #expect(byValue == ["username"])
            #expect(sut.snapshot.filteredEntries.map(\.key) == ["launchCount"])
        }

        @Test("A key in several domains shows once, from the first of persistent, argument, global and registration")
        func domainPrecedence() {
            let storage = FakeUserDefaultsStorage(
                suites: [.standard: ["a": .string("persistent")]],
                otherDomains: [
                    .argument: ["a": .string("argument"), "b": .string("argument")],
                    .global: ["b": .string("global"), "c": .string("global")],
                    .registration: ["c": .string("registration"), "d": .string("registration")]
                ]
            )
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.setShowOtherDomains(true)))
            let expected = [
                DefaultsEntry(key: "a", value: .string("persistent")),
                DefaultsEntry(key: "b", value: .string("argument"), domain: .argument),
                DefaultsEntry(key: "c", value: .string("global"), domain: .global),
                DefaultsEntry(key: "d", value: .string("registration"), domain: .registration)
            ]

            sut.send(UserDefaultsCommand(.reload))

            #expect(sut.snapshot.filteredEntries == expected)
            #expect(sut.snapshot.persistentKeys == ["a"])
        }

        @Test(
            "Editing a key of each kind writes the new value to the shown suite, and the snapshot shows it",
            arguments: [
                (PropertyListValue.string("old"), PropertyListValue.string("new")),
                (.number(NSNumber(value: 1)), .number(NSNumber(value: 2))),
                (.number(NSNumber(value: 1.5)), .number(NSNumber(value: 2.5))),
                (.bool(false), .bool(true)),
                (.date(Date(timeIntervalSince1970: 0)), .date(Date(timeIntervalSince1970: 1_800_000_000))),
                (.data(Data([1])), .data(Data([2, 3]))),
                (.array([.string("a")]), .array([.string("a"), .string("b")])),
                (.dictionary(["k": .string("v")]), .dictionary(["k": .dictionary(["deeper": .bool(true)])]))
            ]
        )
        func editEachKind(old: PropertyListValue, new: PropertyListValue) {
            let storage = FakeUserDefaultsStorage(suites: [.named("group.shared"): ["key": old, "other": .string("same")]])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage))
            sut.send(UserDefaultsCommand(.selectSuite(.named("group.shared"))))

            sut.send(UserDefaultsCommand(.set(new, forKey: "key")))

            #expect(storage.writes == [.set("key", new, .named("group.shared"))])
            #expect(storage.suites[.named("group.shared")]?["key"] == new)
            #expect(sut.snapshot.entries == [DefaultsEntry(key: "key", value: new), DefaultsEntry(key: "other", value: .string("same"))])
        }

        @Test("Editing an element inside an array and a value inside a nested dictionary writes the whole value back")
        func nestedEdits() throws {
            let tabs = PropertyListValue.array([.string("recent"), .string("favorites")])
            let settings = PropertyListValue.dictionary([
                "theme": .dictionary(["accent": .string("orange"), "contrast": .number(1.5)]), "sync": .bool(true)
            ])
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["tabs": tabs, "settings": settings]])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.reload))
            let expectedSettings = PropertyListValue.dictionary([
                "theme": .dictionary(["accent": .string("teal"), "contrast": .number(1.5)]), "sync": .bool(true)
            ])

            sut.send(UserDefaultsCommand(.set(tabs.replacing(at: [.index(1)], with: .string("starred")), forKey: "tabs")))
            sut.send(UserDefaultsCommand(.set(settings.replacing(at: [.key("theme"), .key("accent")], with: .string("teal")), forKey: "settings")))

            #expect(storage.suites[.standard]?["tabs"] == .array([.string("recent"), .string("starred")]))
            #expect(storage.suites[.standard]?["settings"] == expectedSettings)
        }

        @Test("Adding a key of each type writes its starting value to the shown suite and lists it", arguments: PropertyListType.allCases)
        func addEachType(type: PropertyListType) {
            let storage = FakeUserDefaultsStorage()
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage, now: { now }))
            sut.send(UserDefaultsCommand(.selectSuite(.named("group.shared"))))
            let expected = type.initialValue(now: now)

            sut.send(UserDefaultsCommand(.add("added", type: type)))

            #expect(storage.writes == [.set("added", expected, .named("group.shared"))])
            #expect(sut.snapshot.entries == [DefaultsEntry(key: "added", value: expected)])
            #expect(sut.snapshot.entries.first?.value.type == type)
            #expect(storage.suites[.standard] == nil)
        }

        @Test("Deleting a key removes it from the shown suite and the list, and no other suite")
        func deleteKey() {
            let storage = FakeUserDefaultsStorage(suites: [
                .standard: ["doomed": .string("standard's")],
                .named("group.shared"): ["doomed": .string("gone"), "kept": .bool(true)]
            ])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage))
            sut.send(UserDefaultsCommand(.selectSuite(.named("group.shared"))))

            sut.send(UserDefaultsCommand(.remove("doomed")))

            #expect(storage.writes == [.remove("doomed", .named("group.shared"))])
            #expect(sut.snapshot.entries.map(\.key) == ["kept"])
            #expect(storage.suites[.standard]?["doomed"] == .string("standard's"))
        }

        @Test("Deleting the app's value of a registered key resets it: the registered default then shows, read-only")
        func resetToRegisteredDefault() {
            let storage = FakeUserDefaultsStorage(
                suites: [.standard: ["theme": .string("chosen")]],
                otherDomains: [.registration: ["theme": .string("fallback")]]
            )
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.setShowOtherDomains(true)))
            sut.send(UserDefaultsCommand(.reload))
            let before = sut.snapshot.filteredEntries

            sut.send(UserDefaultsCommand(.remove("theme")))

            #expect(before == [DefaultsEntry(key: "theme", value: .string("chosen"))])
            #expect(sut.snapshot.filteredEntries == [DefaultsEntry(key: "theme", value: .string("fallback"), domain: .registration)])
            #expect(sut.snapshot.persistentKeys.isEmpty)
        }

        @Test("Reloading picks up a key changed outside the plugin, which isn't shown until then")
        func refreshPicksUpOutsideChange() {
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["launchCount": .number(1)]])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.reload))
            storage.suites[.standard] = ["launchCount": .number(2), "writtenElsewhere": .string("hello")]
            let beforeReload = sut.snapshot.entries

            sut.send(UserDefaultsCommand(.reload))

            #expect(beforeReload == [DefaultsEntry(key: "launchCount", value: .number(1))])
            #expect(sut.snapshot.entries == [
                DefaultsEntry(key: "launchCount", value: .number(2)),
                DefaultsEntry(key: "writtenElsewhere", value: .string("hello"))
            ])
        }

        @Test("While observed, a burst of outside changes reads the suite once, and a change after that read reads it again")
        func burstCoalesces() async {
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["launchCount": .number(1)]])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.startObserving))
            let readsBefore = storage.reads

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                storage.onRead = {
                    storage.onRead = nil
                    continuation.resume()
                }
                storage.suites[.standard]?["launchCount"] = .number(2)
                storage.announceChange()
                storage.announceChange()
                storage.announceChange()
            }
            let readsAfterBurst = storage.reads
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                storage.onRead = {
                    storage.onRead = nil
                    continuation.resume()
                }
                storage.announceChange()
            }

            #expect(readsAfterBurst == readsBefore + 1)
            #expect(storage.reads == readsBefore + 2)
            #expect(sut.snapshot.entries == [DefaultsEntry(key: "launchCount", value: .number(2))])
            sut.send(UserDefaultsCommand(.stopObserving))
        }

        @Test("Changes are followed while any view that started following is shown, and not after the last stops")
        func observersBalance() {
            let storage = FakeUserDefaultsStorage()
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))

            sut.send(UserDefaultsCommand(.startObserving))
            sut.send(UserDefaultsCommand(.startObserving))
            let afterBoth = storage.observerCount
            sut.send(UserDefaultsCommand(.stopObserving))
            let afterOne = storage.observerCount
            sut.send(UserDefaultsCommand(.stopObserving))
            let afterLast = storage.observerCount
            sut.send(UserDefaultsCommand(.stopObserving))

            #expect(afterBoth == 1)
            #expect(afterOne == 1)
            #expect(afterLast == 0)
            #expect(storage.observerCount == 0)
        }

        @Test("Switching suites reads the newly picked one; a suite the model doesn't offer is ignored")
        func switchSuites() {
            let storage = FakeUserDefaultsStorage(suites: [
                .standard: ["appKey": .string("standard")],
                .named("group.shared"): ["groupKey": .string("shared")],
                .named("group.stranger"): ["strangerKey": .string("no")]
            ])
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage))
            sut.send(UserDefaultsCommand(.reload))
            let standardKeys = sut.snapshot.entries.map(\.key)
            sut.send(UserDefaultsCommand(.selectSuite(.named("group.shared"))))
            let sharedKeys = sut.snapshot.entries.map(\.key)

            sut.send(UserDefaultsCommand(.selectSuite(.named("group.stranger"))))

            #expect(standardKeys == ["appKey"])
            #expect(sharedKeys == ["groupKey"])
            #expect(sut.snapshot.selectedSuite == .named("group.shared"))
            #expect(sut.snapshot.entries.map(\.key) == ["groupKey"])
        }

        @Test("Commands run in the order sent: each write lands, and is read, before the next")
        func commandOrder() {
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["a": .string("1")]])
            let now = Date(timeIntervalSince1970: 0)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: ["group.shared"], storage: storage, now: { now }))
            let expectedWrites: [FakeUserDefaultsStorage.Write] = [
                .set("a", .string("2"), .standard),
                .remove("a", .standard),
                .set("a", .bool(false), .named("group.shared")),
                .set("a", .bool(true), .named("group.shared"))
            ]

            sut.send(UserDefaultsCommand(.set(.string("2"), forKey: "a")))
            sut.send(UserDefaultsCommand(.remove("a")))
            let standardAfterRemove = sut.snapshot.entries
            sut.send(UserDefaultsCommand(.selectSuite(.named("group.shared"))))
            sut.send(UserDefaultsCommand(.add("a", type: .boolean)))
            sut.send(UserDefaultsCommand(.set(.bool(true), forKey: "a")))

            #expect(storage.writes == expectedWrites)
            #expect(standardAfterRemove.isEmpty)
            #expect(sut.snapshot.entries == [DefaultsEntry(key: "a", value: .bool(true))])
        }

        @Test("Naming the suites again offers the new ones and shows Standard, read again while observed")
        func setSuites() {
            let storage = FakeUserDefaultsStorage(suites: [
                .standard: ["appKey": .string("standard")],
                .named("group.old"): ["oldKey": .string("old")]
            ])
            let model = UserDefaultsModel(suites: ["group.old"], storage: storage)
            let sut = DebugDrawerPluginTransport.direct(to: model)
            sut.send(UserDefaultsCommand(.selectSuite(.named("group.old"))))
            sut.send(UserDefaultsCommand(.startObserving))

            model.setSuites(["group.new"])

            #expect(sut.snapshot.suites == [.standard, .named("group.new")])
            #expect(sut.snapshot.selectedSuite == .standard)
            #expect(sut.snapshot.entries.map(\.key) == ["appKey"])
            sut.send(UserDefaultsCommand(.stopObserving))
        }

        @Test("Naming the suites while nothing observes drops the keys read, until the next view appears")
        func setSuitesUnobserved() {
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["appKey": .string("standard")]])
            let model = UserDefaultsModel(suites: [], storage: storage)
            let sut = DebugDrawerPluginTransport.direct(to: model)
            sut.send(UserDefaultsCommand(.reload))

            model.setSuites(["group.a"])

            #expect(sut.snapshot.entries.isEmpty)
            #expect(sut.snapshot.suites == [.standard, .named("group.a")])
        }
    }
#endif
