#if DEBUG
    import Foundation

    /// The app's state behind each category's seam: read into a `ResetPlan`, then deleted
    /// exactly as the plan lists it.
    ///
    /// Main-actor isolated: UserDefaults, the cookie stores and URLCache are read where the app
    /// uses them, and the drawer shows the result. The file walks, which can be long, run off it.
    @MainActor
    struct AppState {
        /// The UserDefaults domains cleared: the app's own first, then its app groups'.
        let domains: [String]
        let preferences: any PreferenceStore
        let keychain: any Keychain
        let container: AppContainer
        let cookies: any CookieStore
        let responseCache: any ResponseCache
        let cleanup: AppStateReset.Cleanup?

        /// The prefix of DebugDrawer's own UserDefaults keys: its layout, its HUD pins, collapsed
        /// plugins and each plugin's settings.
        static let debugDrawerKeyPrefix = "com.debugdrawer."

        /// What a reset would delete now.
        ///
        /// - Parameter includingDebugDrawer: Whether DebugDrawer's own keys and files go too.
        func plan(includingDebugDrawer: Bool) async -> ResetPlan {
            let defaults = domains.map { name in
                DefaultsDomain(
                    name: name,
                    keys: preferences.keys(inDomain: name).filter { includingDebugDrawer || !$0.hasPrefix(Self.debugDrawerKeyPrefix) }
                )
            }
            let keychain: KeychainInventory
            do {
                keychain = try .items(self.keychain.items())
            } catch {
                keychain = .unavailable(error)
            }
            let container = container
            let files = await container.entries(in: container.files, includingDebugDrawer: includingDebugDrawer)
            let caches = await container.entries(in: container.caches, includingDebugDrawer: includingDebugDrawer)
            return ResetPlan(
                defaults: defaults.filter { !$0.keys.isEmpty },
                keychain: keychain,
                files: files,
                caches: caches,
                cookies: await cookies.cookies(),
                urlCache: URLCacheUsage(disk: responseCache.currentDiskUsage, memory: responseCache.currentMemoryUsage),
                cleanup: cleanup?.title
            )
        }

        /// Deletes what `plan` lists for each of `categories`, in `ResetCategory.resetOrder`, and
        /// nothing else. UserDefaults are written to disk and the cookie stores waited on before
        /// it returns, so the app can quit next.
        ///
        /// - Returns: Each category's outcome.
        func reset(_ categories: Set<ResetCategory>, of plan: ResetPlan) async -> ResetResult {
            var outcomes: [ResetCategory: ResetOutcome] = [:]
            for category in ResetCategory.resetOrder where categories.contains(category) && plan.categories.contains(category) {
                outcomes[category] = await reset(category, of: plan)
            }
            return ResetResult(outcomes: outcomes)
        }

        private func reset(_ category: ResetCategory, of plan: ResetPlan) async -> ResetOutcome {
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
                        failures.append(.keychainItem(item.name, error))
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
#endif
