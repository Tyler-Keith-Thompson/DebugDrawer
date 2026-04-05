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
            guard let d = duration else { return "..." }
            if d < 1 { return String(format: "%.0fms", d * 1000) }
            return String(format: "%.2fs", d)
        }

        public var prettyResponseBody: String? {
            guard let data = responseBody else { return nil }
            // Try JSON pretty-print
            if let json = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8)
            {
                return str
            }
            return String(data: data, encoding: .utf8)
        }

        public var prettyRequestBody: String? {
            guard let data = requestBody else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8)
            {
                return str
            }
            return String(data: data, encoding: .utf8)
        }
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
                let q = filterText.lowercased()
                result = result.filter {
                    $0.url.lowercased().contains(q) ||
                        $0.method.lowercased().contains(q) ||
                        ($0.prettyResponseBody?.lowercased().contains(q) ?? false)
                }
            }
            return result
        }

        private var installed = false

        private init() {}

        public func install() {
            guard !installed else { return }
            installed = true
            URLProtocol.registerClass(DebugNetworkProtocol.self)
        }

        func recordStart(_ entry: NetworkEntry) {
            entries.insert(entry, at: 0)
            if entries.count > capacity {
                entries.removeLast(entries.count - capacity)
            }
        }

        func recordCompletion(id: UUID, statusCode: Int?, headers: [String: String]?, body: Data?, duration: TimeInterval?, error: String?) {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].statusCode = statusCode
            entries[idx].responseHeaders = headers
            entries[idx].responseBody = body
            entries[idx].duration = duration
            entries[idx].error = error
            entries[idx].isComplete = true
        }

        public func clear() {
            entries.removeAll()
        }
    }

    // MARK: - URLProtocol interceptor

    final class DebugNetworkProtocol: URLProtocol, @unchecked Sendable {
        private static let handledKey = "com.debugdrawer.network.handled"

        private var entryId: UUID?
        private var startTime: CFAbsoluteTime = 0
        private var responseData = Data()
        private var httpResponse: HTTPURLResponse?
        private var dataTask: URLSessionDataTask?

        override class func canInit(with request: URLRequest) -> Bool {
            guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
            return request.url?.scheme == "http" || request.url?.scheme == "https"
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

            let url = request.url?.absoluteString ?? ""
            let entry = NetworkEntry(
                timestamp: Date(),
                method: request.httpMethod ?? "GET",
                url: url,
                host: request.url?.host ?? "",
                path: request.url?.path ?? "/",
                requestHeaders: request.allHTTPHeaderFields ?? [:],
                requestBody: request.httpBody,
                isComplete: false
            )
            entryId = entry.id
            startTime = CFAbsoluteTimeGetCurrent()

            Task { @MainActor in
                NetworkStore.shared.recordStart(entry)
            }

            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            dataTask = session.dataTask(with: mutable as URLRequest)
            dataTask?.resume()
        }

        override func stopLoading() {
            dataTask?.cancel()
        }
    }

    extension DebugNetworkProtocol: URLSessionDataDelegate {
        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            httpResponse = response as? HTTPURLResponse
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            responseData.append(data)
            client?.urlProtocol(self, didLoad: data)
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let headers = httpResponse?.allHeaderFields as? [String: String]
            let statusCode = httpResponse?.statusCode
            let body = responseData
            let errorMsg = error?.localizedDescription
            let id = entryId

            Task { @MainActor in
                if let id {
                    NetworkStore.shared.recordCompletion(
                        id: id,
                        statusCode: statusCode,
                        headers: headers,
                        body: body,
                        duration: duration,
                        error: errorMsg
                    )
                }
            }

            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    // MARK: - Plugin

    public struct NetworkPlugin: DebugDrawerPlugin {
        public var title = "Network"
        public var icon = "network"

        public init() {}

        public var body: some View {
            NetworkPluginView()
        }
    }

    struct NetworkPluginView: View {
        @ObservedObject private var store = NetworkStore.shared
        @State private var selectedId: UUID?

        private var statsSummary: (total: Int, successRate: String, avgTime: String) {
            let all = store.entries
            let total = all.count
            guard total > 0 else { return (0, "—", "—") }

            let completed = all.filter { $0.isComplete }
            let successes = completed.filter { ($0.statusCode ?? 0) >= 200 && ($0.statusCode ?? 0) < 300 }
            let rate = completed.isEmpty ? "—" : String(format: "%.0f%%", Double(successes.count) / Double(completed.count) * 100)

            let durations = completed.compactMap(\.duration)
            let avg = durations.isEmpty ? "—" : {
                let mean = durations.reduce(0, +) / Double(durations.count)
                return mean < 1 ? String(format: "%.0fms", mean * 1000) : String(format: "%.2fs", mean)
            }()

            return (total, rate, avg)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Stats summary
                if !store.entries.isEmpty {
                    let stats = statsSummary
                    HStack(spacing: 12) {
                        statBadge("\(stats.total)", "Total")
                        statBadge(stats.successRate, "Success")
                        statBadge(stats.avgTime, "Avg Time")
                    }
                    .padding(.vertical, 2)
                }

                // Toolbar
                HStack(spacing: 6) {
                    Text("\(store.filteredEntries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(selection: $store.filterStatus) {
                        ForEach(NetworkStore.StatusFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    } label: { EmptyView() }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)

                    Button("Clear") { store.clear() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                TextField("Filter URL...", text: $store.filterText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                // Request list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.filteredEntries) { entry in
                            requestRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }

        private func requestRow(_ entry: NetworkEntry) -> some View {
            let isSelected = selectedId == entry.id
            return VStack(alignment: .leading, spacing: 0) {
                Button(action: { selectedId = isSelected ? nil : entry.id }) {
                    HStack(spacing: 6) {
                        // Method badge
                        Text(entry.method)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3)
                            .background(methodColor(entry.method).opacity(0.15))
                            .cornerRadius(2)

                        // Status
                        if let code = entry.statusCode {
                            Text("\(code)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(entry.statusColor)
                        } else if !entry.isComplete {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text("ERR")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                        }

                        // Path
                        Text(entry.path)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Duration
                        Text(entry.durationLabel)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSelected {
                    requestDetail(entry)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }

                Divider().padding(.leading, 6)
            }
        }

        private func requestDetail(_ entry: NetworkEntry) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                // URL
                Text(entry.url)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                // Timing + size + actions
                HStack(spacing: 12) {
                    detailBadge("Time", entry.durationLabel)
                    detailBadge("Size", entry.responseSizeLabel)
                    if let code = entry.statusCode {
                        detailBadge("Status", "\(code)")
                    }

                    Spacer()

                    Button("Copy cURL") {
                        debugDrawerCopyToClipboard(buildCurl(for: entry))
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                // URL query parameters
                if let urlObj = URL(string: entry.url),
                   let components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems, !queryItems.isEmpty
                {
                    collapsibleSection("Query Parameters") {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(queryItems, id: \.name) { item in
                                HStack(alignment: .top, spacing: 4) {
                                    Text(item.name + ":")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(item.value ?? "")
                                        .font(.system(size: 9, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                if let error = entry.error {
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(3)
                }

                // Request headers
                if !entry.requestHeaders.isEmpty {
                    collapsibleSection("Request Headers") {
                        headersView(entry.requestHeaders)
                    }
                }

                // Request body
                if let body = entry.prettyRequestBody {
                    collapsibleSection("Request Body") {
                        codeBlock(body)
                    }
                }

                // Response headers
                if let headers = entry.responseHeaders, !headers.isEmpty {
                    collapsibleSection("Response Headers") {
                        headersView(headers)
                    }
                }

                // Response body
                if let body = entry.prettyResponseBody {
                    collapsibleSection("Response Body") {
                        codeBlock(body)
                    }
                }
            }
        }

        private func detailBadge(_ label: String, _ value: String) -> some View {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text(label)
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
        }

        private func collapsibleSection(_ title: String, @ViewBuilder content: @escaping () -> some View) -> some View {
            DisclosureGroup(title) {
                content()
            }
            .font(.caption)
        }

        private func headersView(_ headers: [String: String]) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(headers.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top, spacing: 4) {
                        Text(key + ":")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(headers[key] ?? "")
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(4)
        }

        private func codeBlock(_ text: String) -> some View {
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 9, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(4)
            }
            .frame(maxHeight: 150)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(3)
        }

        private func methodColor(_ method: String) -> Color {
            switch method {
            case "GET": .blue
            case "POST": .green
            case "PUT", "PATCH": .orange
            case "DELETE": .red
            default: .secondary
            }
        }

        private func statBadge(_ value: String, _ label: String) -> some View {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text(label)
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
        }

        private func buildCurl(for entry: NetworkEntry) -> String {
            var parts = ["curl"]

            if entry.method != "GET" {
                parts.append("-X \(entry.method)")
            }

            parts.append("'\(entry.url)'")

            for (key, value) in entry.requestHeaders.sorted(by: { $0.key < $1.key }) {
                let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-H '\(key): \(escaped)'")
            }

            if let body = entry.requestBody, let bodyStr = String(data: body, encoding: .utf8), !bodyStr.isEmpty {
                let escaped = bodyStr.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-d '\(escaped)'")
            }

            return parts.joined(separator: " \\\n  ")
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
