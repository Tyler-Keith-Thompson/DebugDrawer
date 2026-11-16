// watchOS shows the plugins as a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #endif

    /// What the drawer is debugging, read as Xcode's jump bar reads a path: a green dot for the
    /// running app, its name, its version and build in monospaced figures, then the device and
    /// system, which give way first when the line runs short ("● Orders › 1.4.2 (88) › iPad ·
    /// iOS 27.2"). It sits in a well with a hairline edge.
    struct DrawerJumpBar: View {
        let context: Context
        @Environment(\.displayScale) private var displayScale
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var height = DrawerSpacing.jumpBarHeight
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.itemGap
        @ScaledMetric(relativeTo: .body) private var dot = DrawerSpacing.unreadDot

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DrawerSpacing.jumpBarRadius)
            let stacked = dynamicTypeSize.isAccessibilitySize
            // One line, as in Xcode; at accessibility sizes each part takes a line of its own, so
            // none is cut, and the separators go.
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: padding * 0.75))
            layout {
                Circle()
                    .fill(DrawerPalette.ok)
                    .frame(width: dot, height: dot)
                Text(context.appName)
                    .foregroundStyle(DrawerPalette.text)
                    .layoutPriority(2)
                if let release = context.release {
                    if !stacked { separator }
                    Text(release)
                        .monospaced()
                        .foregroundStyle(DrawerPalette.text)
                        .layoutPriority(1)
                }
                if !stacked { separator }
                Text("\(context.device) · \(context.system)")
                    .foregroundStyle(DrawerPalette.secondaryText)
                    .truncationMode(.tail)
                if !stacked { Spacer(minLength: 0) }
            }
            .debugDrawerFont(.secondary)
            .lineLimit(stacked ? 3 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding)
            .padding(.vertical, stacked ? padding / 2 : 0)
            .frame(minHeight: height)
            .background(DrawerPalette.well, in: shape)
            .overlay { shape.strokeBorder(DrawerPalette.separator, lineWidth: 1 / displayScale) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(context.spoken)
        }

        private var separator: some View {
            Text("›")
                .foregroundStyle(DrawerPalette.tertiaryText)
                .accessibilityHidden(true)
        }
    }

    extension DrawerJumpBar {
        /// The parts of the jump bar.
        struct Context: Equatable {
            let appName: String
            let version: String?
            let build: String?
            let device: String
            let system: String

            /// The version and build as the jump bar shows them ("1.4.2 (88)"), either alone, the
            /// version alone when the build repeats it ("1.0.0", not "1.0.0 (1.0.0)", which would
            /// crowd the device off a phone's line), or `nil` when the app declares neither.
            var release: String? {
                switch (version, build) {
                case let (version?, build?) where version == build: version
                case let (version?, build?): "\(version) (\(build))"
                case let (version?, nil): version
                case let (nil, build?): "(\(build))"
                case (nil, nil): nil
                }
            }

            /// What VoiceOver reads: the parts joined by commas.
            var spoken: String {
                [appName, release.map { "version \($0)" }, device, system].compactMap(\.self).joined(separator: ", ")
            }

            /// This process: the main bundle's name and versions, and the device and system it
            /// runs on.
            @MainActor static var current: Context {
                let info = Bundle.main.infoDictionary ?? [:]
                let name = info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? ProcessInfo.processInfo.processName
                return Context(
                    appName: name,
                    version: info["CFBundleShortVersionString"] as? String,
                    build: info["CFBundleVersion"] as? String,
                    device: device,
                    system: system
                )
            }

            @MainActor private static var system: String {
                #if os(macOS)
                    let version = ProcessInfo.processInfo.operatingSystemVersion
                    return "macOS \(version.majorVersion).\(version.minorVersion)"
                #else
                    // Under Mac Catalyst UIDevice names iPadOS's system, which is what the app runs as.
                    return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
                #endif
            }

            @MainActor private static var device: String {
                #if os(macOS)
                    "Mac"
                #else
                    UIDevice.current.model
                #endif
            }
        }
    }
#endif
