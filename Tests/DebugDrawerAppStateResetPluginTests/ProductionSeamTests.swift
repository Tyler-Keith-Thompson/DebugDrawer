#if DEBUG
    @testable import DebugDrawerAppStateResetPlugin
    import Foundation
    import Security
    import Testing

    // The real conformers, against stores the tests make for themselves: a defaults suite and a
    // URL cache of their own, and the keychain's queries. The simulator's keychain is exercised
    // below, on iOS, where a test process has a keychain of its own.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ProductionSeamTests {
        @Test("The keychain is asked for every item of each class in the data protection keychain, synchronized or not, never the login keychain")
        func keychainListQuery() throws {
            let expectedClasses = [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity]

            let queries = KeychainItemClass.allCases.map(_Keychain.listQuery)

            #expect(queries.compactMap { $0[kSecClass as String] as? String } == expectedClasses.map { $0 as String })
            for query in queries {
                #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
                #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String)
                #expect(query[kSecReturnAttributes as String] as? Bool == true)
                #expect(query[kSecReturnPersistentRef as String] as? Bool == true)
                #expect(query[kSecAttrSynchronizable as String] as? String == kSecAttrSynchronizableAny as String)
                #expect(query[kSecAttrAccessGroup as String] == nil)
            }
        }

        @Test("An item is deleted by its persistent reference alone, in the data protection keychain")
        func keychainDeleteQuery() {
            let reference = Data("reference".utf8)
            let item = KeychainItem(
                itemClass: .internetPassword, service: "example.com", account: "alice", label: nil, persistentReference: reference
            )

            let actual = _Keychain.deleteQuery(for: item)

            #expect(actual[kSecValuePersistentRef as String] as? Data == reference)
            #expect(actual[kSecClass as String] as? String == kSecClassInternetPassword as String)
            #expect(actual[kSecUseDataProtectionKeychain as String] as? Bool == true)
            #expect(actual[kSecAttrAccount as String] == nil)
        }

        @Test("A keychain item is named by service and account, by label without them, and by its class without either")
        func keychainItemNames() {
            let password = KeychainItem(itemClass: .genericPassword, service: "api", account: "alice", label: "ignored", persistentReference: Data())
            let serviceOnly = KeychainItem(itemClass: .genericPassword, service: "api", account: "", label: nil, persistentReference: Data())
            let labelled = KeychainItem(itemClass: .certificate, service: nil, account: nil, label: "Example CA", persistentReference: Data())
            let unnamed = KeychainItem(itemClass: .key, service: nil, account: nil, label: nil, persistentReference: Data())

            #expect(password.name == "api · alice")
            #expect(serviceOnly.name == "api")
            #expect(labelled.name == "Example CA")
            #expect(unnamed.name == "Unnamed key")
        }

        @Test("The real defaults list a suite's keys and remove exactly those asked for")
        func preferences() throws {
            let suite = "com.debugdrawer.tests.appStateReset.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "onboarded")
            defaults.set(3, forKey: "counter")
            defaults.set("kept", forKey: "kept")
            let sut = _PreferenceStore(appDomain: "com.example.not-this-one")

            let before = sut.keys(inDomain: suite)
            sut.remove(["onboarded", "counter"], fromDomain: suite)
            let after = sut.keys(inDomain: suite)

            #expect(before == ["counter", "kept", "onboarded"])
            #expect(after == ["kept"])
            #expect(defaults.object(forKey: "onboarded") == nil)
        }

        @Test("A URL cache reports its usage and, cleared, answers no request")
        func urlCache() async throws {
            // In memory alone: Bazel's sandbox won't let URLCache truncate a store on disk.
            let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, directory: nil)
            let url = try #require(URL(string: "https://example.com/orders"))
            let request = URLRequest(url: url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            cache.storeCachedResponse(CachedURLResponse(response: response, data: Data(repeating: 1, count: 4096)), for: request)
            let sut: any ResponseCache = cache

            let memory = sut.currentMemoryUsage
            sut.removeAllCachedResponses()

            #expect(memory > 0)
            #expect(cache.cachedResponse(for: request) == nil)
        }
    }
#endif
