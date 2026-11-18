import CoreLocation

/// A location manager's delegate that keeps every location it is given, in order, and streams
/// each one as it comes, for a test to await.
final class RecordingLocationDelegate: NSObject, CLLocationManagerDelegate {
    private(set) var locations: [CLLocation] = []
    /// Each location as the delegate is given it.
    let updates: AsyncStream<CLLocation>
    private let continuation: AsyncStream<CLLocation>.Continuation

    override init() {
        (updates, continuation) = AsyncStream.makeStream()
        super.init()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.locations += locations
        for location in locations {
            continuation.yield(location)
        }
    }
}
