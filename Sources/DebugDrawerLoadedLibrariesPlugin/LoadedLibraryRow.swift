#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A library: its type badge (the app, a framework or a dylib), its name and version, its
    /// path cut in the middle so the file name shows, and its UUID and load address.
    struct LoadedLibraryRow: View {
        let library: LoadedLibrary

        var body: some View {
            DebugDrawerTypeBadgeRow(
                library.name,
                kind: library.badgeKind,
                path: library.path,
                detail: "\(library.uuid?.uuidString ?? "no UUID") · \(library.loadAddressLabel)",
                version: library.version
            )
        }
    }

    extension LoadedLibrary {
        /// The load address in hexadecimal, as the row and Copy List show it.
        var loadAddressLabel: String {
            String(format: "0x%llx", UInt64(loadAddress))
        }

        /// The app's executable is the app; a binary inside a .framework bundle is a framework;
        /// anything else is a dylib.
        fileprivate var badgeKind: DebugDrawerTypeBadgeRow.Kind {
            if category == .app, !path.contains(".framework/") { return .app }
            return path.contains(".framework/") ? .framework : .dylib
        }
    }
#endif
