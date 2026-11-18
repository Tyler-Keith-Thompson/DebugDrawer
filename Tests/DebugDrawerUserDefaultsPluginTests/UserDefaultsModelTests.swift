#if DEBUG
    import Combine
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    // Each test that reaches the real defaults writes to a suite of its own, named with a UUID,
    // and removes its persistent domain afterwards.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsModelTests {
        @Test("A suite the host names is offered after Standard, and picking it lists that suite's keys")
        func hostSuiteListed() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set("ada", forKey: "username")
            suite.set(3, forKey: "launchCount")
            let sut = UserDefaultsModel(suites: [name])
            let expectedSuites: [UserDefaultsSuite] = [.standard, .named(name)]
            let expected = [
                DefaultsEntry(key: "launchCount", value: .number(3)),
                DefaultsEntry(key: "username", value: .string("ada"))
            ]

            sut.selectedSuite = .named(name)

            #expect(sut.suites == expectedSuites)
            #expect(sut.filteredEntries == expected)
        }

        @Test("A repeated or empty suite name is offered once or not at all")
        func duplicateSuites() {
            let expected: [UserDefaultsSuite] = [.standard, .named("group.a"), .named("group.b")]

            let actual = UserDefaultsModel(suites: ["group.a", "", "group.b", "group.a"], storage: FakeUserDefaultsStorage()).suites

            #expect(actual == expected)
        }

        @Test("Adding a key of each type writes a value of that type to the suite", arguments: PropertyListType.allCases)
        func addEachType(type: PropertyListType) throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let sut = UserDefaultsModel(suites: [name], now: { now })
            sut.selectedSuite = .named(name)

            sut.add("added", type: type)

            let stored = try #require(suite.object(forKey: "added"))
            let actual = try #require(PropertyListValue(propertyList: stored))
            #expect(actual.type == type)
            #expect(actual == type.initialValue(now: now))
            #expect(sut.filteredEntries.map(\.key) == ["added"])
        }

        @Test("Adding a key writes the Foundation type UserDefaults reads it back as", arguments: PropertyListType.allCases)
        func addFoundationType(type: PropertyListType) throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = UserDefaultsModel(suites: [name])
            sut.selectedSuite = .named(name)

            sut.add("added", type: type)

            let booleanTypeID = CFBooleanGetTypeID()
            let object = suite.object(forKey: "added")
            switch type {
            case .string: #expect(object as? String == "")
            case .number:
                let number = try #require(object as? NSNumber)
                #expect(CFGetTypeID(number) != booleanTypeID)
                #expect(number.intValue == 0)
            case .boolean:
                let number = try #require(object as? NSNumber)
                #expect(CFGetTypeID(number) == booleanTypeID)
                #expect(!number.boolValue)
            case .date: #expect(suite.object(forKey: "added") is Date)
            case .data: #expect(suite.data(forKey: "added") == Data())
            case .array: #expect(suite.array(forKey: "added")?.isEmpty == true)
            case .dictionary: #expect(suite.dictionary(forKey: "added")?.isEmpty == true)
            }
        }

        @Test("Editing an element inside an array and a value inside a nested dictionary persists in the suite")
        func nestedEditsPersist() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set(["recent", "favorites"], forKey: "tabs")
            suite.set(["theme": ["accent": "orange", "contrast": 1.5], "sync": true], forKey: "settings")
            let sut = UserDefaultsModel(suites: [name])
            sut.selectedSuite = .named(name)
            let tabs = try #require(sut.entries.first { $0.key == "tabs" }?.value)
            let settings = try #require(sut.entries.first { $0.key == "settings" }?.value)

            sut.set(tabs.replacing(at: [.index(1)], with: .string("starred")), forKey: "tabs")
            sut.set(settings.replacing(at: [.key("theme"), .key("accent")], with: .string("teal")), forKey: "settings")

            let reread = try #require(UserDefaults(suiteName: name))
            #expect(reread.stringArray(forKey: "tabs") == ["recent", "starred"])
            let theme = try #require(reread.dictionary(forKey: "settings")?["theme"] as? [String: Any])
            #expect(theme["accent"] as? String == "teal")
            #expect(theme["contrast"] as? Double == 1.5)
            #expect(reread.dictionary(forKey: "settings")?["sync"] as? Bool == true)
        }

        @Test("A key the app writes from outside the plugin appears in the list without anyone reloading")
        func outsideWriteUpdates() async throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let sut = UserDefaultsModel(suites: [name])
            sut.selectedSuite = .named(name)
            sut.startObservingChanges()
            var subscription: AnyCancellable?

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                subscription = sut.$entries.first { $0.contains { $0.key == "writtenElsewhere" } }.sink { _ in continuation.resume() }
                // Another instance of the suite, as the app's own code would hold.
                UserDefaults(suiteName: name)?.set("hello", forKey: "writtenElsewhere")
            }

            subscription?.cancel()
            sut.stopObservingChanges()
            #expect(sut.entries.first { $0.key == "writtenElsewhere" }?.value == .string("hello"))
        }

        @Test("A burst of changes reads the suite once, and a change after that read reads it again")
        func burstCoalesces() async {
            let storage = FakeUserDefaultsStorage(suites: [.standard: ["launchCount": 1]])
            let sut = UserDefaultsModel(suites: [], storage: storage)
            sut.startObservingChanges()
            let readsBefore = storage.reads

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                storage.onRead = {
                    storage.onRead = nil
                    continuation.resume()
                }
                storage.suites[.standard]?["launchCount"] = 2
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
            #expect(sut.entries == [DefaultsEntry(key: "launchCount", value: .number(2))])
        }

        @Test("Changes are followed while any view that started following is shown, and not after the last stops")
        func observersBalance() {
            let storage = FakeUserDefaultsStorage()
            let sut = UserDefaultsModel(suites: [], storage: storage)

            sut.startObservingChanges()
            sut.startObservingChanges()
            let afterBoth = storage.observerCount
            sut.stopObservingChanges()
            let afterOne = storage.observerCount
            sut.stopObservingChanges()
            let afterLast = storage.observerCount
            sut.stopObservingChanges()

            #expect(afterBoth == 1)
            #expect(afterOne == 1)
            #expect(afterLast == 0)
            #expect(storage.observerCount == 0)
        }

        @Test("Removing a key removes it from the shown suite and the list")
        func removeKey() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set("gone", forKey: "doomed")
            let sut = UserDefaultsModel(suites: [name])
            sut.selectedSuite = .named(name)

            sut.remove("doomed")

            #expect(suite.object(forKey: "doomed") == nil)
            #expect(sut.filteredEntries.isEmpty)
        }

        @Test("Switching suites reads the newly picked one, and Standard's keys don't show in a named suite")
        func switchSuites() {
            let storage = FakeUserDefaultsStorage(suites: [
                .standard: ["appKey": "standard"],
                .named("group.shared"): ["groupKey": "shared"]
            ])
            let sut = UserDefaultsModel(suites: ["group.shared"], storage: storage)
            sut.reload()
            let standardKeys = sut.entries.map(\.key)

            sut.selectedSuite = .named("group.shared")

            #expect(standardKeys == ["appKey"])
            #expect(sut.entries.map(\.key) == ["groupKey"])
        }

        @Test("Other domains' keys hide unless shown, and the search matches a key or a value without regard to case")
        func filters() {
            let storage = FakeUserDefaultsStorage(
                suites: [.standard: ["launchCount": 3, "username": "Ada"]],
                otherDomains: [.global: ["NSLanguages": ["en"]]]
            )
            let sut = UserDefaultsModel(suites: [], storage: storage)
            sut.reload()
            let hidden = sut.filteredEntries.map(\.key)
            sut.showOtherDomains = true
            let shown = sut.filteredEntries.map(\.key)
            sut.showOtherDomains = false
            sut.searchText = "ADA"
            let byValue = sut.filteredEntries.map(\.key)
            sut.searchText = "launch"

            let actual = sut.filteredEntries.map(\.key)

            #expect(hidden == ["launchCount", "username"])
            #expect(shown == ["NSLanguages", "launchCount", "username"])
            #expect(byValue == ["username"])
            #expect(actual == ["launchCount"])
        }

        @Test("A registered default that no property list can hold is left out of the list")
        func nonPropertyListLeftOut() {
            let storage = FakeUserDefaultsStorage(otherDomains: [.registration: ["odd": NSObject(), "fine": "yes"]])
            let sut = UserDefaultsModel(suites: [], storage: storage)

            sut.reload()

            #expect(sut.entries.map(\.key) == ["fine"])
        }

        @Test("Keys the app wrote that look like the system's, such as CountryCode and NSFWFilterEnabled, are listed")
        func systemLookingKeysListed() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set("NZ", forKey: "CountryCode")
            suite.set(true, forKey: "NSFWFilterEnabled")
            suite.set("Ada", forKey: "AppleIDName")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = UserDefaultsModel(suites: [], storage: storage)
            let expected = [
                DefaultsEntry(key: "AppleIDName", value: .string("Ada")),
                DefaultsEntry(key: "CountryCode", value: .string("NZ")),
                DefaultsEntry(key: "NSFWFilterEnabled", value: .bool(true))
            ]

            sut.reload()

            #expect(sut.filteredEntries == expected)
        }

        @Test("The list is the persistent domain's: a registered default and the global domain's keys stay out unless shown")
        func persistentDomainOnly() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            // The registration domain is the process's, so the key is one no other test uses.
            let registered = "DebugDrawerTests.registered.\(UUID().uuidString)"
            suite.register(defaults: [registered: 7])
            suite.set("ada", forKey: "username")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = UserDefaultsModel(suites: [], storage: storage)
            let expected = [DefaultsEntry(key: "username", value: .string("ada"))]

            sut.reload()
            let hidden = sut.filteredEntries
            sut.showOtherDomains = true
            let shown = sut.filteredEntries

            #expect(hidden == expected)
            #expect(shown.first { $0.key == registered } == DefaultsEntry(key: registered, value: .number(7), domain: .registration))
            #expect(shown.first { $0.key == "username" }?.domain == .persistent)
            #expect(shown.filter { $0.domain == .persistent } == expected)
            #expect(sut.persistentKeys == ["username"])
        }

        @Test("Deleting a key that is also registered removes the app's value; the registered default then shows read-only")
        func deleteOverRegisteredDefault() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let key = "DebugDrawerTests.registered.\(UUID().uuidString)"
            suite.register(defaults: [key: "fallback"])
            suite.set("chosen", forKey: key)
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = UserDefaultsModel(suites: [], storage: storage)
            sut.showOtherDomains = true
            sut.reload()
            let before = sut.filteredEntries.first { $0.key == key }

            sut.remove(key)

            let actual = sut.filteredEntries.first { $0.key == key }
            #expect(before == DefaultsEntry(key: key, value: .string("chosen")))
            #expect(suite.persistentDomain(forName: name)?[key] == nil)
            #expect(actual == DefaultsEntry(key: key, value: .string("fallback"), domain: .registration))
        }

        @Test("A key in several domains shows once, from the first of persistent, argument, global and registration")
        func domainPrecedence() {
            let storage = FakeUserDefaultsStorage(
                suites: [.standard: ["a": "persistent"]],
                otherDomains: [
                    .argument: ["a": "argument", "b": "argument"],
                    .global: ["b": "global", "c": "global"],
                    .registration: ["c": "registration", "d": "registration"]
                ]
            )
            let sut = UserDefaultsModel(suites: [], storage: storage)
            sut.showOtherDomains = true
            let expected = [
                DefaultsEntry(key: "a", value: .string("persistent")),
                DefaultsEntry(key: "b", value: .string("argument"), domain: .argument),
                DefaultsEntry(key: "c", value: .string("global"), domain: .global),
                DefaultsEntry(key: "d", value: .string("registration"), domain: .registration)
            ]

            sut.reload()

            #expect(sut.filteredEntries == expected)
        }

        @Test("Editing an integer stores an integer, a real a real, and a Boolean a Boolean, read back from the suite")
        func editsKeepTheStoredType() throws {
            let name = "DebugDrawerTests.\(UUID().uuidString)"
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set(3, forKey: "launchCount")
            suite.set(2.5, forKey: "volume")
            suite.set(true, forKey: "sync")
            suite.set(NSNumber(value: 1), forKey: "flag")
            let sut = UserDefaultsModel(suites: [name])
            sut.selectedSuite = .named(name)
            let launchCount = try #require(sut.entries.first { $0.key == "launchCount" }?.value)
            let volume = try #require(sut.entries.first { $0.key == "volume" }?.value)
            let flag = try #require(sut.entries.first { $0.key == "flag" }?.value)
            let booleanTypeID = CFBooleanGetTypeID()

            sut.set(try launchCount.replacement(parsing: "4", encoding: .hex), forKey: "launchCount")
            sut.set(try volume.replacement(parsing: "3", encoding: .hex), forKey: "volume")
            sut.set(try flag.replacement(parsing: "0", encoding: .hex), forKey: "flag")
            sut.set(.bool(false), forKey: "sync")

            let integer = try #require(suite.object(forKey: "launchCount") as? NSNumber)
            let real = try #require(suite.object(forKey: "volume") as? NSNumber)
            let zero = try #require(suite.object(forKey: "flag") as? NSNumber)
            let boolean = try #require(suite.object(forKey: "sync") as? NSNumber)
            #expect(integer == 4)
            #expect(!CFNumberIsFloatType(integer as CFNumber))
            #expect(CFGetTypeID(integer) != booleanTypeID)
            #expect(real == 3)
            #expect(CFNumberIsFloatType(real as CFNumber))
            #expect(zero == 0)
            #expect(!CFNumberIsFloatType(zero as CFNumber))
            #expect(CFGetTypeID(zero) != booleanTypeID)
            #expect(CFGetTypeID(boolean) == booleanTypeID)
            #expect(boolean == false)
            #expect(flag.type == .number)
        }
    }
#endif
