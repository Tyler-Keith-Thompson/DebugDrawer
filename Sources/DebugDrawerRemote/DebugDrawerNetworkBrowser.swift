import Combine
import Foundation
import Network

// The viewer's list of devices to pick from. It browses only between `start()` and `stop()`, so a
// viewer that connects by address (a simulator on the same Mac, over 127.0.0.1) never browses,
// and the Mac shows no local network prompt for it.

#if DEBUG
    /// The apps on the local network whose ``DebugDrawerNetworkServer`` advertises over Bonjour.
    ///
    /// ```swift
    /// let browser = DebugDrawerNetworkBrowser()
    /// browser.start()
    /// // browser.devices fills as apps appear, and empties as they go.
    /// ```
    ///
    /// The viewing app lists ``DebugDrawerBonjourService/type`` under `NSBonjourServices` and
    /// gives an `NSLocalNetworkUsageDescription`. Release builds get a stand-in that finds
    /// nothing.
    @MainActor
    public final class DebugDrawerNetworkBrowser: ObservableObject {
        private let browser: any ServiceBrowser
        /// The apps found, by name, each speaking this build's pairing.
        @Published public private(set) var devices: [DebugDrawerNetworkDevice] = []
        /// Whether the browser is browsing.
        @Published public private(set) var isBrowsing = false

        /// A browser of the local network; it browses once started.
        public convenience init() {
            self.init(browser: _ServiceBrowser())
        }

        /// A browser that browses through `browser`.
        init(browser: any ServiceBrowser) {
            self.browser = browser
        }

        /// Starts browsing. Does nothing while browsing.
        public func start() {
            guard !isBrowsing else { return }
            isBrowsing = true
            browser.start { [weak self] services in
                guard let self, isBrowsing else { return }
                devices = services
                    .filter { $0.txtRecord[DebugDrawerBonjourService.Key.version] == DebugDrawerBonjourService.protocolVersion }
                    .map(DebugDrawerNetworkDevice.init(service:))
                    .sorted { ($0.name, $0.appName ?? "") < ($1.name, $1.appName ?? "") }
            }
        }

        /// Stops browsing, and forgets the devices found.
        public func stop() {
            browser.cancel()
            isBrowsing = false
            devices = []
        }
    }

    extension DebugDrawerNetworkDevice {
        /// The device a browse found as `service`.
        fileprivate init(service: BrowsedService) {
            self.init(
                name: service.name,
                appName: service.txtRecord[DebugDrawerBonjourService.Key.appName],
                bundleIdentifier: service.txtRecord[DebugDrawerBonjourService.Key.bundleIdentifier],
                platform: service.txtRecord[DebugDrawerBonjourService.Key.platform],
                endpoint: service.endpoint
            )
        }
    }
#else
    // The release stand-in: the same members, finding nothing.

    /// Release builds browse nothing: this stand-in finds no devices.
    @MainActor
    public final class DebugDrawerNetworkBrowser: ObservableObject {
        /// Always empty.
        @Published public private(set) var devices: [DebugDrawerNetworkDevice] = []
        /// Always `false`.
        @Published public private(set) var isBrowsing = false

        /// A browser that never browses.
        public init() {}

        /// Does nothing.
        public func start() {}

        /// Does nothing.
        public func stop() {}
    }
#endif
