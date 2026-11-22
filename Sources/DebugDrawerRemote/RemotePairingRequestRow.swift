#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One viewer asking to pair: its name, its code large enough to read across a desk, and
    /// Reject.
    struct RemotePairingRequestRow: View {
        let request: DebugDrawerPairingRequest
        let onReject: () -> Void

        var body: some View {
            DebugDrawerRow(request.viewerName, systemImage: "laptopcomputer") {
                Text(request.code.groupedInThrees)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .debugDrawerForegroundStyle(.primary)
                    // Read digit by digit, as the person types it, rather than as two numbers.
                    // Not selectable: the code is typed on the viewer, never copied, and on
                    // macOS selectable text with a label of its own sent AppKit's accessibility
                    // into a loop that overflowed the main thread's stack (DD-288).
                    .accessibilityLabel("Code \(request.code.map(String.init).joined(separator: " "))")
            } accessory: {
                Button("Reject", role: .destructive, action: onReject)
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityLabel("Reject \(request.viewerName)")
                    .help("Turn this viewer away")
            }
            .accessibilityElement(children: .contain)
        }
    }

    extension String {
        /// `"042917"` as `"042 917"`, the way a six-digit code is easiest to read out.
        fileprivate var groupedInThrees: String {
            stride(from: 0, to: count, by: 3).map { offset in
                let start = index(startIndex, offsetBy: offset)
                return String(self[start ..< (index(start, offsetBy: 3, limitedBy: endIndex) ?? endIndex)])
            }
            .joined(separator: " ")
        }
    }
#endif
