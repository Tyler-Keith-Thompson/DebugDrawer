#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os

    /// The Network plugin's saved files (ignore list, mock rules and bodies, conditioning
    /// profiles) in memory, so a test's model never touches the disk.
    final class InMemoryNetworkStorage: NetworkIgnoreListStorage, NetworkMockStorage, NetworkConditionStorage {
        private let files = OSAllocatedUnfairLock(initialState: [String: Data]())

        func readIgnoreList() throws -> Data? { files.withLock { $0["ignored"] } }
        func writeIgnoreList(_ data: Data) throws { files.withLock { $0["ignored"] = data } }
        func readRules() throws -> Data? { files.withLock { $0["rules"] } }
        func writeRules(_ data: Data) throws { files.withLock { $0["rules"] = data } }
        func readProfiles() throws -> Data? { files.withLock { $0["profiles"] } }
        func writeProfiles(_ data: Data) throws { files.withLock { $0["profiles"] = data } }

        func addBody(_ data: Data, fileExtension: String?) throws -> String {
            let name = "body-\(UUID().uuidString)"
            files.withLock { $0[name] = data }
            return name
        }

        func writeBody(_ data: Data, named name: String) throws { files.withLock { $0[name] = data } }
        func body(named name: String) -> Data? { files.withLock { $0[name] } }
        func removeBody(named name: String) { files.withLock { $0[name] = nil } }
    }
#endif
