import Foundation
import Network

#if DEBUG
    /// Network.framework's `NWBrowser`, browsing for ``DebugDrawerBonjourService/type`` services
    /// with their TXT records.
    @MainActor
    final class _ServiceBrowser: ServiceBrowser {
        private var browser: NWBrowser?

        // A browser dropped without `stop()` stops browsing with it.
        isolated deinit {
            browser?.cancel()
        }

        func start(_ results: @escaping @MainActor ([BrowsedService]) -> Void) {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: DebugDrawerBonjourService.type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { found, _ in
                let services = found.compactMap(BrowsedService.init(result:))
                Task { @MainActor in results(services) }
            }
            self.browser = browser
            browser.start(queue: DispatchQueue(label: "DebugDrawerRemote.ServiceBrowser"))
        }

        func cancel() {
            browser?.cancel()
            browser = nil
        }
    }

    extension BrowsedService {
        /// The service `result` found, or `nil` when it isn't a Bonjour service.
        fileprivate init?(result: NWBrowser.Result) {
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            var txtRecord: [String: String] = [:]
            if case let .bonjour(record) = result.metadata {
                txtRecord = record.dictionary
            }
            self.init(name: name, endpoint: result.endpoint, txtRecord: txtRecord)
        }
    }
#endif
