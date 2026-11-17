#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import SwiftUI

    // MARK: - Network request model

    public struct NetworkEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let method: String
        public let url: String
        public let host: String
        public let path: String
        public let requestHeaders: [String: String]
        public let requestBody: Data?
        public var statusCode: Int?
        public var responseHeaders: [String: String]?
        public var responseBody: Data?
        public var duration: TimeInterval?
        public var error: String?
        public var isComplete: Bool
        /// Timing of the request's last transaction, from `URLSessionTaskMetrics`.
        public var metrics: NetworkTimingMetrics?
        /// The name of the mock rule that answered the request, or `nil` when the network did.
        public var mockRuleName: String?
        /// What a conditioning profile did to the request, or `nil` when none applied.
        public var conditionEffect: NetworkConditionEffect?

        /// Whether the request failed: the server answered with a status of 400 or more, or the
        /// request never got an answer (a transport error).
        var isFailure: Bool {
            error != nil || (statusCode ?? 0) >= 400
        }

        public var responseSizeLabel: String {
            guard let data = responseBody else { return "—" }
            if data.count < 1024 { return "\(data.count) B" }
            if data.count < 1024 * 1024 { return "\(data.count / 1024) KB" }
            return String(format: "%.1f MB", Double(data.count) / (1024 * 1024))
        }

        public var durationLabel: String {
            guard let duration else { return "..." }
            if duration < 1 { return String(format: "%.0fms", duration * 1000) }
            return String(format: "%.2fs", duration)
        }

        public var prettyResponseBody: String? {
            responseBody?.prettyBody
        }

        public var prettyRequestBody: String? {
            requestBody?.prettyBody
        }
    }

    extension Data {
        /// This body as pretty-printed JSON with sorted keys, or as UTF-8 text when it isn't JSON.
        var prettyBody: String? {
            if let json = try? JSONSerialization.jsonObject(with: self),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: pretty, encoding: .utf8) {
                return text
            }
            return String(data: self, encoding: .utf8)
        }
    }

    /// How a request ended: what came back and how long it took, or why it failed.
    struct NetworkCompletion {
        var statusCode: Int?
        var headers: [String: String]?
        var body: Data?
        var duration: TimeInterval?
        var error: String?
    }

    // MARK: - Network store

    @MainActor
    public final class NetworkStore: ObservableObject {
        public static let shared = NetworkStore()

        @Published public private(set) var entries: [NetworkEntry] = []
        @Published public var filterText = ""
        @Published public var filterStatus: StatusFilter = .all

        public var capacity = 200

        public enum StatusFilter: String, CaseIterable {
            case all = "All"
            case success = "2xx"
            case clientError = "4xx"
            case serverError = "5xx"
            case errors = "Errors"
        }

        public var filteredEntries: [NetworkEntry] {
            var result = entries
            switch filterStatus {
            case .all: break
            case .success: result = result.filter { ($0.statusCode ?? 0) >= 200 && ($0.statusCode ?? 0) < 300 }
            case .clientError: result = result.filter { ($0.statusCode ?? 0) >= 400 && ($0.statusCode ?? 0) < 500 }
            case .serverError: result = result.filter { ($0.statusCode ?? 0) >= 500 }
            case .errors: result = result.filter(\.isFailure)
            }
            if !filterText.isEmpty {
                let query = filterText.lowercased()
                result = result.filter {
                    $0.url.lowercased().contains(query) ||
                        $0.method.lowercased().contains(query) ||
                        ($0.prettyResponseBody?.lowercased().contains(query) ?? false)
                }
            }
            return result
        }

        private var installed = false

        private init() {}

        public func install() {
            guard !installed else { return }
            installed = true
            // Register for URLSession.shared
            URLProtocol.registerClass(DebugNetworkProtocol.self)
            // Swizzle URLSessionConfiguration so custom sessions also get intercepted
            URLSessionConfiguration.swizzleProtocolClasses()
        }

        func recordStart(_ entry: NetworkEntry) {
            entries.insert(entry, at: 0)
            if entries.count > capacity {
                entries.removeLast(entries.count - capacity)
            }
        }

        func recordCompletion(id: UUID, _ completion: NetworkCompletion) {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].statusCode = completion.statusCode
            entries[idx].responseHeaders = completion.headers
            entries[idx].responseBody = completion.body
            entries[idx].duration = completion.duration
            entries[idx].error = completion.error
            entries[idx].isComplete = true
        }

        func recordMetrics(id: UUID, metrics: NetworkTimingMetrics) {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].metrics = metrics
        }

        public func clear() {
            entries.removeAll()
        }
    }

    // MARK: - Plugin

    public struct NetworkPlugin: DebugDrawerPlugin {
        public var title = "Network"
        public var category = "Logs & Network"
        public var icon = "network"

        public init() {}

        public var body: some View {
            NetworkPluginView()
        }

        /// How many requests were captured, and how many of them failed; the conditions that are
        /// on, when any are.
        public var headerAccessory: some View {
            NetworkHeaderAccessoryView()
        }

        /// The conditions that are on ("3G active"), so they show with the drawer closed.
        @MainActor public var hud: NetworkConditionsHUD? {
            NetworkConditionsHUD(conditions: .shared)
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the network inspector. Registers a URLProtocol to capture HTTP traffic, and
        /// loads the saved mock rules, which answer the requests they match from then on, and the
        /// saved conditioning profiles, which slow down or fail the requests to their hosts.
        ///
        /// - Parameters:
        ///   - mocks: Rules to add to the saved ones, at the end; one whose id is saved already is
        ///     skipped, so the drawer's edits to it last from launch to launch.
        ///   - conditions: Profiles to add to the saved ones, at the end, by id as `mocks` are.
        func installNetwork(mocks: [NetworkMockRule] = [], conditions: [NetworkConditionProfile] = []) {
            NetworkMocksModel.shared.load(adding: mocks)
            NetworkConditionsModel.shared.load(adding: conditions)
            NetworkStore.shared.install()
            registerGlobal(NetworkPlugin())
        }
    }
#endif
