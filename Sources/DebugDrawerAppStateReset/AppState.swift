import Foundation

/// The app's state behind each category's seam: read into a `ResetPlan`, then deleted
/// exactly as the plan lists it.
///
/// Main-actor isolated: UserDefaults, the cookie stores and URLCache are read where the app
/// uses them, and the drawer or a sidecar shows the result. The file walks, which can be long,
/// run off it.
@MainActor
package struct AppState {
    /// The UserDefaults domains cleared: the app's own first, then its app groups'.
    package let domains: [String]
    package let preferences: any PreferenceStore
    package let keychain: any Keychain
    package var container: AppContainer
    package let cookies: any CookieStore
    package let responseCache: any ResponseCache
    package let cleanup: AppStateReset.Cleanup?
    /// The suite DebugDrawer keeps its own state in (`UserDefaults.debugDrawer`), cleared only
    /// when the reset includes DebugDrawer's own settings; `nil` for none.
    package var debugDrawerDomain: String?
    /// Whether a keychain item that couldn't be deleted is named with its account
    /// (`KeychainItem.name`), as the drawer, in the app itself, names it; a sidecar's report names
    /// it without (`KeychainItem.listedName`).
    package var namesKeychainAccounts = true

    /// The prefixes of the DebugDrawer keys kept in the app's own domain: the drawer's, such as
    /// Tweaks' values and Feature Flags' overrides, and the receiver's, such as the log levels a
    /// session raised, which it reverts after a relaunch.
    package static let debugDrawerKeyPrefixes = ["com.debugdrawer.", "DebugDrawer."]

    /// The app's state behind these seams.
    package init(
        domains: [String],
        preferences: any PreferenceStore,
        keychain: any Keychain,
        container: AppContainer,
        cookies: any CookieStore,
        responseCache: any ResponseCache,
        cleanup: AppStateReset.Cleanup?,
        debugDrawerDomain: String? = nil
    ) {
        self.domains = domains
        self.preferences = preferences
        self.keychain = keychain
        self.container = container
        self.cookies = cookies
        self.responseCache = responseCache
        self.cleanup = cleanup
        self.debugDrawerDomain = debugDrawerDomain
    }

    /// What a reset of `categories` would delete now; a category left out is read as holding
    /// nothing, so the keychain, say, isn't touched when it isn't asked for.
    ///
    /// - Parameters:
    ///   - categories: The categories to read; all of them by default.
    ///   - includingDebugDrawer: Whether DebugDrawer's own keys, suite and files go too.
    package func plan(
        of categories: Set<AppStateReset.Category> = Set(AppStateReset.Category.allCases), includingDebugDrawer: Bool
    ) async -> ResetPlan {
        let drawerDomains = includingDebugDrawer ? debugDrawerDomain.map { [$0] } ?? [] : []
        let defaults = categories.contains(.userDefaults)
            ? (domains + drawerDomains).map { name in
                DefaultsDomain(
                    name: name,
                    keys: preferences.keys(inDomain: name).filter { key in
                        includingDebugDrawer || !Self.debugDrawerKeyPrefixes.contains { key.hasPrefix($0) }
                    }
                )
            }
            : []
        let keychain: KeychainInventory
        do {
            keychain = categories.contains(.keychain) ? try .items(self.keychain.items()) : .items([])
        } catch {
            keychain = .unavailable(error)
        }
        let container = container
        let files = categories.contains(.files) ? await container.entries(in: container.files, includingDebugDrawer: includingDebugDrawer) : []
        let caches = categories.contains(.caches) ? await container.entries(in: container.caches, includingDebugDrawer: includingDebugDrawer) : []
        let cookies = categories.contains(.cookies) ? await self.cookies.cookies() : []
        let urlCache = categories.contains(.urlCache)
            ? URLCacheUsage(disk: responseCache.currentDiskUsage, memory: responseCache.currentMemoryUsage)
            : URLCacheUsage(disk: 0, memory: 0)
        return ResetPlan(
            defaults: defaults.filter { !$0.keys.isEmpty },
            keychain: keychain,
            files: files,
            caches: caches,
            cookies: cookies,
            urlCache: urlCache,
            cleanup: cleanup?.title
        )
    }

    /// Deletes what `plan` lists for each of `categories`, in `AppStateReset.Category.resetOrder`, and
    /// nothing else. UserDefaults are written to disk and the cookie stores waited on before
    /// it returns, so the app can quit next.
    ///
    /// - Returns: Each category's outcome.
    package func reset(_ categories: Set<AppStateReset.Category>, of plan: ResetPlan) async -> ResetResult {
        var outcomes: [AppStateReset.Category: ResetOutcome] = [:]
        for category in AppStateReset.Category.resetOrder where categories.contains(category) && plan.categories.contains(category) {
            outcomes[category] = await reset(category, of: plan)
        }
        return ResetResult(outcomes: outcomes)
    }

    private func reset(_ category: AppStateReset.Category, of plan: ResetPlan) async -> ResetOutcome {
        switch category {
        case .appCleanup:
            return await runCleanup()
        case .keychain:
            return deleteKeychainItems(plan.keychain)
        case .userDefaults:
            for domain in plan.defaults {
                preferences.remove(domain.keys, fromDomain: domain.name)
            }
            return .cleared(plan.defaults.map(\.keys.count).reduce(0, +))
        case .cookies:
            await cookies.delete(plan.cookies)
            return .cleared(plan.cookies.count)
        case .urlCache:
            responseCache.removeAllCachedResponses()
            return .cleared(1)
        case .caches:
            return ResetOutcome(count: plan.caches.count, failures: await container.delete(plan.caches))
        case .files:
            return ResetOutcome(count: plan.files.count, failures: await container.delete(plan.files))
        }
    }

    private func runCleanup() async -> ResetOutcome {
        guard let cleanup else { return .cleared(0) }
        do {
            try await cleanup.perform()
            return .cleared(1)
        } catch {
            return .failed(cleared: 0, failures: [.cleanup(error.localizedDescription)])
        }
    }

    private func deleteKeychainItems(_ inventory: KeychainInventory) -> ResetOutcome {
        switch inventory {
        case let .unavailable(error):
            return .failed(cleared: 0, failures: [.keychainUnavailable(error)])
        case let .items(items):
            var failures: [ResetFailure] = []
            for item in items {
                do throws(KeychainError) {
                    try keychain.delete(item)
                } catch {
                    failures.append(.keychainItem(namesKeychainAccounts ? item.name : item.listedName, error))
                }
            }
            return ResetOutcome(count: items.count, failures: failures)
        }
    }
}

extension ResetOutcome {
    /// The outcome of deleting `count` things of which `failures` couldn't be.
    fileprivate init(count: Int, failures: [ResetFailure]) {
        self = failures.isEmpty ? .cleared(count) : .failed(cleared: count - failures.count, failures: failures)
    }
}
