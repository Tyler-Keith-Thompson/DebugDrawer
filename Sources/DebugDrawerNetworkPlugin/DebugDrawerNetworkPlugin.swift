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

        public var statusColor: Color {
            guard let code = statusCode else { return .secondary }
            switch code {
            case 200 ..< 300: return .green
            case 300 ..< 400: return .blue
            case 400 ..< 500: return .orange
            default: return .red
            }
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
            guard let data = responseBody else { return nil }
            // Try JSON pretty-print
            if let json = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                return str
            }
            return String(data: data, encoding: .utf8)
        }

        public var prettyRequestBody: String? {
            guard let data = requestBody else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                return str
            }
            return String(data: data, encoding: .utf8)
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
            case .errors: result = result.filter { $0.error != nil || ($0.statusCode ?? 0) >= 400 }
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
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the network inspector. Registers a URLProtocol to capture HTTP traffic.
        func installNetwork() {
            NetworkStore.shared.install()
            registerGlobal(NetworkPlugin())
        }
    }
#endif
