#if DEBUG
    import Combine
    import Foundation
    #if os(macOS)
        import IOKit.ps
    #elseif os(iOS)
        import UIKit
    #endif

    // The Mac reads IOKit's power sources and hears of a change through IOKit's run-loop source;
    // iOS reads `UIDevice`, which posts its changes only while battery monitoring is on (the
    // monitor turns it on while it samples). Elsewhere there is no battery to read.

    /// The system's battery and power source.
    @MainActor
    final class _BatteryReader: BatteryReader {
        #if os(macOS)
            /// IOKit's source on the main run loop while observing, and the handler it calls,
            /// retained for the C callback and released on stop.
            private var observation: (source: CFRunLoopSource, handler: Unmanaged<ChangeHandler>)?
        #else
            /// The notifications' subscription while observing; `nil` otherwise.
            private var observation: AnyCancellable?
        #endif

        func read() -> BatteryReading {
            #if os(macOS)
                let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
                let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
                guard let source = sources.first,
                      let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any]
                else {
                    return BatteryReading(level: -1, isCharging: false, powerSource: "AC Power")
                }
                return BatteryReading(
                    level: description[kIOPSCurrentCapacityKey] as? Int ?? -1,
                    isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                    powerSource: description[kIOPSPowerSourceStateKey] as? String ?? "Unknown"
                )
            #elseif os(iOS)
                let level = UIDevice.current.batteryLevel
                let state = UIDevice.current.batteryState
                let isCharging = state == .charging || state == .full
                return BatteryReading(
                    level: level >= 0 ? Int(level * 100) : -1,
                    isCharging: isCharging,
                    powerSource: isCharging ? "AC Power" : "Battery"
                )
            #else
                return BatteryReading(level: -1, isCharging: false, powerSource: "Unknown")
            #endif
        }

        func startObserving(_ change: @escaping @MainActor () -> Void) {
            stopObserving()
            #if os(macOS)
                let handler = Unmanaged.passRetained(ChangeHandler(change))
                let callback: IOPowerSourceCallbackType = { context in
                    guard let context else { return }
                    // IOKit calls back on the run loop the source was added to: the main one.
                    MainActor.assumeIsolated {
                        Unmanaged<ChangeHandler>.fromOpaque(context).takeUnretainedValue().change()
                    }
                }
                guard let source = IOPSNotificationCreateRunLoopSource(callback, handler.toOpaque())?.takeRetainedValue() else {
                    handler.release()
                    return
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                observation = (source, handler)
            #elseif os(iOS)
                observation = NotificationCenter.default
                    .publisher(for: UIDevice.batteryLevelDidChangeNotification)
                    .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
                    .receive(on: DispatchQueue.main)
                    .sink { _ in change() }
            #endif
        }

        func stopObserving() {
            #if os(macOS)
                guard let observation else { return }
                CFRunLoopRemoveSource(CFRunLoopGetMain(), observation.source, .commonModes)
                observation.handler.release()
                self.observation = nil
            #else
                observation?.cancel()
                observation = nil
            #endif
        }
    }

    #if os(macOS)
        /// The handler IOKit's C callback reaches through its context pointer.
        @MainActor
        private final class ChangeHandler {
            let change: @MainActor () -> Void

            init(_ change: @escaping @MainActor () -> Void) {
                self.change = change
            }
        }
    #endif
#endif
