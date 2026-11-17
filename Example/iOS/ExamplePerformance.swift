import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// The macOS example has its own copy of the busy thread: each app is its own module, and the
// examples share no code.

/// A thread named "example-busy" that spins until stopped, for the Performance plugin's Threads
/// list to put at the top.
@MainActor
final class ExampleBusyThread: ObservableObject {
    /// The name the Threads list shows.
    static let name = "example-busy"

    @Published private(set) var isRunning = false
    private var thread: Thread?

    func start() {
        guard thread == nil else { return }
        // Spins until cancelled: Thread's own flag, safe to read from the thread and set from
        // the main one.
        let busy = Thread {
            while !Thread.current.isCancelled {}
        }
        busy.name = Self.name
        busy.qualityOfService = .utility
        busy.start()
        thread = busy
        isRunning = true
    }

    func stop() {
        thread?.cancel()
        thread = nil
        isRunning = false
    }
}

/// Starts and stops the busy thread.
struct ExampleBusyThreadRow: View {
    @StateObject private var busyThread = ExampleBusyThread()

    var body: some View {
        if busyThread.isRunning {
            Button("Stop the Busy Thread") { busyThread.stop() }
        } else {
            Button("Start a Busy Thread (\(ExampleBusyThread.name))") { busyThread.start() }
        }
    }
}

#if canImport(UIKit)
    /// The app's own observer of the memory warning, and when it last fired: the Performance
    /// plugin's Simulate Memory Warning reaches it.
    struct ExampleMemoryWarningReadout: View {
        @State private var last: Date?
        @State private var count = 0

        var body: some View {
            Text(last.map { "Last memory warning: \($0.formatted(date: .omitted, time: .standard)) (\(count))" } ?? "Last memory warning: none")
                .font(.body.monospacedDigit())
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    last = Date()
                    count += 1
                }
        }
    }
#endif
