#if DEBUG
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import os

    /// Storage in memory: what was saved, how often, and a save failure the test sets.
    final class FakeMockupStorage: MockupStorage, Sendable {
        private struct Storage {
            var mockup: Data?
            var settings: DesignOverlaySettings?
            var settingsSaves = 0
            var failsToSave = false
        }

        // A lock, not an actor: the protocol is synchronous, as the folder's file reads are.
        private let storage: OSAllocatedUnfairLock<Storage>

        init(mockup: Data? = nil, settings: DesignOverlaySettings? = nil, failsToSave: Bool = false) {
            storage = OSAllocatedUnfairLock(initialState: Storage(mockup: mockup, settings: settings, failsToSave: failsToSave))
        }

        /// The mockup saved, or `nil`.
        var mockup: Data? {
            storage.withLock(\.mockup)
        }

        /// The settings saved, or `nil`.
        var settings: DesignOverlaySettings? {
            storage.withLock(\.settings)
        }

        /// How many times settings were saved.
        var settingsSaves: Int {
            storage.withLock(\.settingsSaves)
        }

        func loadMockup() -> Data? {
            mockup
        }

        func saveMockup(_ data: Data) throws(MockupFailure) {
            let fails = storage.withLock { storage in
                if !storage.failsToSave { storage.mockup = data }
                return storage.failsToSave
            }
            if fails { throw .notSaved }
        }

        func removeMockup() {
            storage.withLock { $0.mockup = nil }
        }

        func loadSettings() -> DesignOverlaySettings? {
            settings
        }

        func saveSettings(_ settings: DesignOverlaySettings) {
            storage.withLock {
                $0.settings = settings
                $0.settingsSaves += 1
            }
        }
    }
#endif
