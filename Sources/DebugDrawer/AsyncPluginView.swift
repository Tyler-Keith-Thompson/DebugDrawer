#if DEBUG
    import SwiftUI

    /// A view that runs an async task when it appears, showing a progress indicator
    /// until the result is available. Designed for debug drawer plugins that need
    /// to do potentially slow work (file I/O, network, scanning) without blocking
    /// the main thread.
    ///
    /// Usage:
    /// ```swift
    /// AsyncPluginView {
    ///     await scanFileSystem()
    /// } content: { result in
    ///     FileTreeView(root: result)
    /// }
    /// ```
    public struct AsyncPluginView<Result: Sendable, Content: View>: View {
        private let task: @Sendable () async -> Result
        private let content: (Result) -> Content

        @State private var result: Result?
        @State private var isLoading = false

        public init(
            task: @escaping @Sendable () async -> Result,
            @ViewBuilder content: @escaping (Result) -> Content
        ) {
            self.task = task
            self.content = content
        }

        public var body: some View {
            Group {
                if let result {
                    content(result)
                } else if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            }
            .task {
                isLoading = true
                result = await task()
                isLoading = false
            }
        }

        /// Trigger a reload (clears current result and re-runs the task).
        public mutating func reload() {
            result = nil
        }
    }

    /// A variant that loads on demand (e.g. when a button is pressed) rather than
    /// on appear. Shows nothing until `load()` is called.
    public struct OnDemandPluginView<Result: Sendable, Content: View>: View {
        private let task: @Sendable () async -> Result
        private let content: (Result) -> Content
        private let loadLabel: String

        @State private var result: Result?
        @State private var isLoading = false

        public init(
            loadLabel: String = "Load",
            task: @escaping @Sendable () async -> Result,
            @ViewBuilder content: @escaping (Result) -> Content
        ) {
            self.loadLabel = loadLabel
            self.task = task
            self.content = content
        }

        public var body: some View {
            Group {
                if let result {
                    content(result)
                } else if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } else {
                    Button(loadLabel) { load() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
            }
        }

        private func load() {
            isLoading = true
            Task {
                let value = await task()
                result = value
                isLoading = false
            }
        }
    }
#endif
