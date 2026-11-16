#if DEBUG
    import Combine
    @testable import DebugDrawerTweaksPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweakStoreTests {
        @Test("A value written through one store reads back, typed, from a fresh store over the same storage")
        func persistsAcrossStores() {
            let storage = FakeTweakStorage()
            let server = Tweak.picker("Server", key: "server", default: Server.production)
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120)
            TweakStore(storage: storage).set(.staging, for: server)
            TweakStore(storage: storage).set(45, for: timeout)
            let sut = TweakStore(storage: storage)

            let actualServer: Server = sut.value(of: server)
            let actualTimeout: Int = sut.value(of: timeout)

            #expect(actualServer == .staging)
            #expect(actualTimeout == 45)
        }

        @Test("Values persist in UserDefaults under the key prefix, and a fresh store over the same defaults reads them")
        func persistsInUserDefaults() throws {
            let suiteName = "com.debugdrawer.tests.tweaks.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
            let greeting = Tweak.text("Greeting", key: "greeting", default: "Hello")
            let launch = TweakStore(storage: UserDefaultsTweakStorage(defaults: defaults))
            launch.set(true, for: newCheckout)
            launch.set("", for: greeting)
            let sut = TweakStore(storage: UserDefaultsTweakStorage(defaults: defaults))

            let actualCheckout: Bool = sut.value(of: newCheckout)
            let actualGreeting: String = sut.value(of: greeting)

            #expect(actualCheckout == true)
            #expect(actualGreeting == "")
            #expect(defaults.object(forKey: "com.debugdrawer.tweaks.newCheckout") as? Bool == true)
            #expect(defaults.object(forKey: "newCheckout") == nil)
        }

        @Test("A tweak with nothing stored reads its default")
        func defaultWhenUnset() {
            let sut = TweakStore(storage: FakeTweakStorage())
            let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120)

            let actual: Int = sut.value(of: timeout)

            #expect(actual == 30)
        }

        @Test("Resetting removes the stored values, so the tweaks read their defaults")
        func reset() {
            let storage = FakeTweakStorage(["a": .bool(true), "b": .int(4), "other": .string("kept")])
            let sut = TweakStore(storage: storage)

            sut.reset(keys: ["a", "b"])

            #expect(storage.values == ["other": .string("kept")])
        }

        @Test("A tweak's publisher sends the current value, then each change to its key alone, once per new value")
        func publisher() {
            let storage = FakeTweakStorage(["newCheckout": .bool(true)])
            let sut = TweakStore(storage: storage)
            let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
            var actual: [Bool] = []
            let subscription = sut.publisher(for: newCheckout).sink { actual.append($0) }
            defer { subscription.cancel() }

            sut.setStoredValue(.bool(true), forKey: "newCheckout")
            sut.setStoredValue(.int(3), forKey: "otherKey")
            sut.setStoredValue(.bool(false), forKey: "newCheckout")
            sut.setStoredValue(nil, forKey: "newCheckout")
            sut.setStoredValue(.bool(true), forKey: "newCheckout")

            #expect(actual == [true, false, true])
        }

        @Test("A write tells the store's observers before it changes")
        func objectWillChange() {
            let sut = TweakStore(storage: FakeTweakStorage())
            var actual = 0
            let subscription = sut.objectWillChange.sink { actual += 1 }
            defer { subscription.cancel() }

            sut.setStoredValue(.bool(true), forKey: "newCheckout")

            #expect(actual == 1)
        }

        @Test("A store given new storage reads through it")
        func useStorage() {
            let sut = TweakStore(storage: FakeTweakStorage())
            let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)

            sut.use(FakeTweakStorage(["newCheckout": .bool(true)]))

            let actual: Bool = sut.value(of: newCheckout)
            #expect(actual == true)
        }
    }
#endif
