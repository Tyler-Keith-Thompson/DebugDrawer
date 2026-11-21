#if DEBUG
    import DebugDrawer
    import DebugDrawerTestSupport
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation
    import Testing

    // The real store, `_UserDefaultsStorage`, under the model. Each test writes to a suite of its
    // own, named with a UUID, which also stands in for the standard defaults, and removes its
    // persistent domain afterwards: none reads or writes `.standard` or the app's own domain. A
    // registered default goes in the process's registration domain, under a key no other test uses.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsStorageTests {
        @Test("A suite the host names is offered after Standard, and picking it lists that suite's keys")
        func hostSuiteListed() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set("ada", forKey: "username")
            suite.set(3, forKey: "launchCount")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [name], storage: storage))
            let expectedSuites: [UserDefaultsSuite] = [.standard, .named(name)]
            let expected = [
                DefaultsEntry(key: "launchCount", value: .number(3)),
                DefaultsEntry(key: "username", value: .string("ada"))
            ]

            sut.send(UserDefaultsCommand(.selectSuite(.named(name))))

            #expect(sut.snapshot.suites == expectedSuites)
            #expect(sut.snapshot.filteredEntries == expected)
        }

        @Test("Adding a key writes the Foundation type UserDefaults reads it back as", arguments: PropertyListType.allCases)
        func addFoundationType(type: PropertyListType) throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [name], storage: storage, now: { now }))
            sut.send(UserDefaultsCommand(.selectSuite(.named(name))))

            sut.send(UserDefaultsCommand(.add("added", type: type)))

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
            case .date: #expect(object as? Date == now)
            case .data: #expect(suite.data(forKey: "added") == Data())
            case .array: #expect(suite.array(forKey: "added")?.isEmpty == true)
            case .dictionary: #expect(suite.dictionary(forKey: "added")?.isEmpty == true)
            }
            #expect(sut.snapshot.filteredEntries == [DefaultsEntry(key: "added", value: type.initialValue(now: now))])
        }

        @Test("Editing an element inside an array and a value inside a nested dictionary persists in the suite")
        func nestedEditsPersist() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set(["recent", "favorites"], forKey: "tabs")
            suite.set(["theme": ["accent": "orange", "contrast": 1.5], "sync": true], forKey: "settings")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [name], storage: storage))
            sut.send(UserDefaultsCommand(.selectSuite(.named(name))))
            let tabs = try #require(sut.snapshot.entries.first { $0.key == "tabs" }?.value)
            let settings = try #require(sut.snapshot.entries.first { $0.key == "settings" }?.value)

            sut.send(UserDefaultsCommand(.set(tabs.replacing(at: [.index(1)], with: .string("starred")), forKey: "tabs")))
            sut.send(UserDefaultsCommand(.set(settings.replacing(at: [.key("theme"), .key("accent")], with: .string("teal")), forKey: "settings")))

            let reread = try #require(UserDefaults(suiteName: name))
            #expect(reread.stringArray(forKey: "tabs") == ["recent", "starred"])
            let theme = try #require(reread.dictionary(forKey: "settings")?["theme"] as? [String: Any])
            #expect(theme["accent"] as? String == "teal")
            #expect(theme["contrast"] as? Double == 1.5)
            #expect(reread.dictionary(forKey: "settings")?["sync"] as? Bool == true)
        }

        @Test("A key the app writes from outside the plugin appears in the list without anyone reloading")
        func outsideWriteUpdates() async throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [name], storage: storage))
            sut.send(UserDefaultsCommand(.selectSuite(.named(name))))
            sut.send(UserDefaultsCommand(.startObserving))
            let snapshots = sut.snapshots()

            // Another instance of the suite, as the app's own code would hold.
            UserDefaults(suiteName: name)?.set("hello", forKey: "writtenElsewhere")
            var actual: DefaultsEntry?
            for await snapshot in snapshots {
                actual = snapshot.entries.first { $0.key == "writtenElsewhere" }
                if actual != nil { break }
            }

            sut.send(UserDefaultsCommand(.stopObserving))
            #expect(actual == DefaultsEntry(key: "writtenElsewhere", value: .string("hello")))
        }

        @Test("Removing a key removes it from the shown suite and the list")
        func removeKey() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set("gone", forKey: "doomed")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [name], storage: storage))
            sut.send(UserDefaultsCommand(.selectSuite(.named(name))))

            sut.send(UserDefaultsCommand(.remove("doomed")))

            #expect(suite.object(forKey: "doomed") == nil)
            #expect(sut.snapshot.filteredEntries.isEmpty)
        }

        @Test("Keys the app wrote that look like the system's, such as CountryCode and NSFWFilterEnabled, are listed")
        func systemLookingKeysListed() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set("NZ", forKey: "CountryCode")
            suite.set(true, forKey: "NSFWFilterEnabled")
            suite.set("Ada", forKey: "AppleIDName")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            let expected = [
                DefaultsEntry(key: "AppleIDName", value: .string("Ada")),
                DefaultsEntry(key: "CountryCode", value: .string("NZ")),
                DefaultsEntry(key: "NSFWFilterEnabled", value: .bool(true))
            ]

            sut.send(UserDefaultsCommand(.reload))

            #expect(sut.snapshot.filteredEntries == expected)
        }

        @Test("The list is the persistent domain's: a registered default and the global domain's keys stay out unless shown")
        func persistentDomainOnly() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let registered = "DebugDrawerTests.registered.\(UUID().uuidString)"
            suite.register(defaults: [registered: 7])
            suite.set("ada", forKey: "username")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            let expected = [DefaultsEntry(key: "username", value: .string("ada"))]

            sut.send(UserDefaultsCommand(.reload))
            let hidden = sut.snapshot.filteredEntries
            sut.send(UserDefaultsCommand(.setShowOtherDomains(true)))
            let shown = sut.snapshot.filteredEntries

            #expect(hidden == expected)
            #expect(shown.first { $0.key == registered } == DefaultsEntry(key: registered, value: .number(7), domain: .registration))
            #expect(shown.first { $0.key == "username" }?.domain == .persistent)
            #expect(shown.filter { $0.domain == .persistent } == expected)
            #expect(sut.snapshot.persistentKeys == ["username"])
        }

        @Test("Deleting a key that is also registered removes the app's value; the registered default then shows read-only")
        func deleteOverRegisteredDefault() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let key = "DebugDrawerTests.registered.\(UUID().uuidString)"
            suite.register(defaults: [key: "fallback"])
            suite.set("chosen", forKey: key)
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [], storage: storage))
            sut.send(UserDefaultsCommand(.setShowOtherDomains(true)))
            sut.send(UserDefaultsCommand(.reload))
            let before = sut.snapshot.filteredEntries.first { $0.key == key }

            sut.send(UserDefaultsCommand(.remove(key)))

            let actual = sut.snapshot.filteredEntries.first { $0.key == key }
            #expect(before == DefaultsEntry(key: key, value: .string("chosen")))
            #expect(suite.persistentDomain(forName: name)?[key] == nil)
            #expect(actual == DefaultsEntry(key: key, value: .string("fallback"), domain: .registration))
        }

        @Test("Editing an integer stores an integer, a real a real, and a Boolean a Boolean, read back from the suite")
        func editsKeepTheStoredType() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            suite.set(3, forKey: "launchCount")
            suite.set(2.5, forKey: "volume")
            suite.set(true, forKey: "sync")
            suite.set(NSNumber(value: 1), forKey: "flag")
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let sut = DebugDrawerPluginTransport.direct(to: UserDefaultsModel(suites: [name], storage: storage))
            sut.send(UserDefaultsCommand(.selectSuite(.named(name))))
            let launchCount = try #require(sut.snapshot.entries.first { $0.key == "launchCount" }?.value)
            let volume = try #require(sut.snapshot.entries.first { $0.key == "volume" }?.value)
            let flag = try #require(sut.snapshot.entries.first { $0.key == "flag" }?.value)
            let booleanTypeID = CFBooleanGetTypeID()

            try sut.send(UserDefaultsCommand(.set(launchCount.replacement(parsing: "4", encoding: .hex), forKey: "launchCount")))
            try sut.send(UserDefaultsCommand(.set(volume.replacement(parsing: "3", encoding: .hex), forKey: "volume")))
            try sut.send(UserDefaultsCommand(.set(flag.replacement(parsing: "0", encoding: .hex), forKey: "flag")))
            sut.send(UserDefaultsCommand(.set(.bool(false), forKey: "sync")))

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

        @Test("A number decoded from a snapshot writes back as the same kind of number")
        func decodedNumbersWriteBack() throws {
            let name = temporarySuiteName("DebugDrawerTests")
            let suite = try #require(UserDefaults(suiteName: name))
            defer { suite.removePersistentDomain(forName: name) }
            let storage = _UserDefaultsStorage(standard: suite, standardDomainName: name)
            let integer = try JSONDecoder().decode(PropertyListValue.self, from: Data(#"{"integer":4}"#.utf8))
            let real = try JSONDecoder().decode(PropertyListValue.self, from: Data(#"{"real":4}"#.utf8))

            storage.set(integer, forKey: "integer", in: .standard)
            storage.set(real, forKey: "real", in: .standard)

            let storedInteger = try #require(suite.object(forKey: "integer") as? NSNumber)
            let storedReal = try #require(suite.object(forKey: "real") as? NSNumber)
            #expect(!CFNumberIsFloatType(storedInteger as CFNumber))
            #expect(CFNumberIsFloatType(storedReal as CFNumber))
        }
    }
#endif
