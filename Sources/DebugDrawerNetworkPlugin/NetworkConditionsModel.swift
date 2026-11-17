#if DEBUG
    import Foundation
    import os

    /// The conditioning profiles on the main actor, for the drawer: each change is saved and handed
    /// to the profiles the URL protocol conditions requests by.
    @MainActor
    final class NetworkConditionsModel: ObservableObject {
        /// The model `installNetwork()` loads and the plugin shows, over the app's storage, the
        /// profiles the URL protocol reads, a dispatch timer and the system's random numbers.
        static let shared = NetworkConditionsModel(
            storage: _NetworkConditionStorage(directory: _NetworkMockStorage.defaultDirectory),
            active: .shared,
            scheduler: _NetworkConditionScheduler(),
            random: _NetworkConditionRandomSource()
        )

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkConditionsModel")

        /// Every profile, in the order they are tried.
        @Published private(set) var profiles: [NetworkConditionProfile] = []
        /// What went wrong last, if anything.
        @Published private(set) var issue: NetworkMocksIssue?

        let storage: any NetworkConditionStorage
        let active: NetworkConditions
        let scheduler: any NetworkConditionScheduler
        let random: any NetworkConditionRandomSource

        /// - Parameters:
        ///   - storage: Where the profiles are kept between launches.
        ///   - active: The profiles requests are conditioned by, which each change replaces.
        ///   - scheduler: What times the latency and the bandwidth cap.
        ///   - random: What decides which requests fail.
        init(
            storage: any NetworkConditionStorage,
            active: NetworkConditions,
            scheduler: any NetworkConditionScheduler,
            random: any NetworkConditionRandomSource
        ) {
            self.storage = storage
            self.active = active
            self.scheduler = scheduler
            self.random = random
        }

        /// The profiles that are on, in order.
        var enabledProfiles: [NetworkConditionProfile] {
            profiles.filter(\.isEnabled)
        }

        /// Reads the saved profiles and conditions requests by them, then adds each of `profiles`
        /// that isn't saved already (by id), at the end. A saved profile of the same id wins, so the
        /// drawer's edits to a profile the app adds at every launch last.
        func load(adding profiles: [NetworkConditionProfile] = []) {
            var loaded: [NetworkConditionProfile] = []
            do {
                if let data = try storage.readProfiles() {
                    loaded = try NetworkConditionProfileFile.decode(data)
                }
                issue = nil
            } catch let error as NetworkMockRuleFile.ReadError {
                Self.logger.error("Saved network conditions not loaded: \(String(describing: error), privacy: .public)")
                issue = switch error {
                case .unreadable: .unreadable
                case let .unsupportedVersion(version): .unsupportedVersion(version)
                }
            } catch {
                Self.logger.error("Saved network conditions not read: \(error.localizedDescription, privacy: .public)")
                issue = .unreadable
            }
            let added = profiles.filter { profile in !loaded.contains { $0.id == profile.id } }
            self.profiles = loaded + added
            if added.isEmpty {
                activate()
            } else {
                commit()
            }
        }

        /// Saves `profile`: in place of the profile with its id, or at the end.
        func save(_ profile: NetworkConditionProfile) {
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
            commit()
        }

        /// Turns the profile with `id` on or off.
        func setEnabled(_ isEnabled: Bool, id: NetworkConditionProfile.ID) {
            guard let index = profiles.firstIndex(where: { $0.id == id }), profiles[index].isEnabled != isEnabled else { return }
            profiles[index].isEnabled = isEnabled
            commit()
        }

        /// Moves the profile with `id` `offset` places later (negative for earlier), within the
        /// list.
        func move(_ id: NetworkConditionProfile.ID, by offset: Int) {
            guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
            let destination = min(max(index + offset, 0), profiles.count - 1)
            guard destination != index else { return }
            profiles.insert(profiles.remove(at: index), at: destination)
            commit()
        }

        /// Deletes the profile with `id`.
        func delete(_ id: NetworkConditionProfile.ID) {
            guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles.remove(at: index)
            commit()
        }

        /// Saves the profiles and conditions requests by them.
        private func commit() {
            do {
                try storage.writeProfiles(NetworkConditionProfileFile.encode(profiles))
                if issue == .notSaved { issue = nil }
            } catch {
                Self.logger.error("Network conditions not saved: \(error.localizedDescription, privacy: .public)")
                issue = .notSaved
            }
            activate()
        }

        private func activate() {
            active.activate(profiles, scheduler: scheduler, random: random)
        }
    }
#endif
