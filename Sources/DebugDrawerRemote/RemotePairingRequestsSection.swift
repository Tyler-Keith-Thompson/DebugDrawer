#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The viewers asking to pair, oldest first: each one's name, the code its person must type
    /// into it, and Reject.
    struct RemotePairingRequestsSection: View {
        let requests: [DebugDrawerPairingRequest]
        let reject: (DebugDrawerPairingRequest) -> Void

        var body: some View {
            DebugDrawerSection("Pairing requests") {
                ForEach(requests) { request in
                    RemotePairingRequestRow(request: request) {
                        reject(request)
                    }
                }
            } footer: {
                if requests.isEmpty {
                    Text("No viewer is asking to pair.")
                } else {
                    Text("Type the code into the viewer to pair it. Each code works once.")
                }
            }
        }
    }
#endif
