import Foundation
import SwiftUI

// The iOS example has its own copy of this file, with the memory warning readout the Mac has no
// use for: each app is its own module, and the examples share no code.

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
