import CoreLocation

/// A location manager's delegate that keeps every location it is given, in order.
final class RecordingLocationDelegate: NSObject, CLLocationManagerDelegate {
    private(set) var locations: [CLLocation] = []

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.locations += locations
    }
}
