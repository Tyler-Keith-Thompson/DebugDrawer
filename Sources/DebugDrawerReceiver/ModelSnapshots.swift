import Combine
import Foundation

// A model's snapshots as JSON, for the receiver to write to the store: the current one, then one
// after each change, skipping one that encodes to the bytes before it. The drawer's
// `DebugDrawerPluginTransport.snapshots()` does the same for its servers, but it is debug-only
// and lives in the drawer's module, which a release build doesn't link, so the receiver keeps
// these few lines of its own. A change is announced before it lands (`objectWillChange`), and the
// reader resumes on the main actor only after the code making it has returned, so the snapshot it
// reads holds it; changes that land while the writer is busy fold into one.

/// `model`'s snapshots as JSON, the current one first, each different from the one before.
@MainActor
func encodedSnapshots<Model: DebugDrawerPluginModel>(of model: Model) -> AsyncStream<Data> {
    AsyncStream { continuation in
        let forwarding = Task { @MainActor in
            let (changes, change) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let subscription = model.objectWillChange.sink { _ in change.yield() }
            var previous: Data?
            @MainActor func forward() {
                guard let encoded = try? TransportMessage.payload(model.snapshot), encoded != previous else { return }
                previous = encoded
                continuation.yield(encoded)
            }
            forward()
            for await _ in changes {
                forward()
            }
            subscription.cancel()
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
    }
}
