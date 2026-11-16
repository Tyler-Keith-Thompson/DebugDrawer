#if DEBUG
    import CoreBluetooth

    /// Bluetooth, through Core Bluetooth. It has no request call: creating a central manager shows
    /// the prompt, and its delegate hears the answer.
    @MainActor
    final class BluetoothPermissionReader: NSObject, SystemPermissionReader, @preconcurrency CBCentralManagerDelegate {
        /// The manager whose creation showed the prompt, kept until it is answered.
        private var manager: CBCentralManager?
        private var answered: CheckedContinuation<Void, Never>?

        func status(of _: DeclaredPermission) async -> PermissionStatus {
            PermissionStatus(CBManager.authorization)
        }

        func request(_: DeclaredPermission) async {
            guard manager == nil else { return }
            await withCheckedContinuation { continuation in
                answered = continuation
                // No queue: the delegate is called on the main queue, as its isolation needs.
                manager = CBCentralManager(delegate: self, queue: nil)
            }
        }

        func centralManagerDidUpdateState(_: CBCentralManager) {
            guard CBManager.authorization != .notDetermined else { return }
            answered?.resume()
            answered = nil
            manager = nil
        }
    }

    extension PermissionStatus {
        init(_ status: CBManagerAuthorization) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .restricted: self = .restricted
            case .denied: self = .denied
            case .allowedAlways: self = .authorized
            @unknown default: self = .unknown(rawValue: status.rawValue)
            }
        }
    }
#endif
