#if DEBUG
    import SwiftUI

    /// How an app's screen offers the plugins it serves.
    ///
    /// A segmented picker splits its width evenly between the plugins, so on an iPhone in
    /// portrait four or more of them cut their names short ("Acce…", "Metri…"), and a host may
    /// serve twenty. Where the width is that narrow the screen is a list instead, a row per plugin
    /// that pushes it, as the drawer's watch list and the watch sidecar show plugins: every name
    /// is read in full, however many there are.
    enum SidecarPluginLayout: Equatable {
        /// The status and session along the top, a segmented picker of the plugins over the one
        /// picked, and the report along the bottom: a Mac window, or an iPad at regular width.
        case picker
        /// A list of the status and session, a row per plugin that pushes it, and the report: an
        /// iPhone, an iPad in a narrow split (compact width), and the watch.
        case rows

        #if os(iOS)
            /// The layout for a horizontal size class: rows when compact, the picker otherwise.
            /// On Mac Catalyst a window as narrow as an iPhone's screen is compact too, and gets
            /// the rows for the same reason.
            init(horizontalSizeClass: UserInterfaceSizeClass?) {
                self = horizontalSizeClass == .compact ? .rows : .picker
            }
        #elseif os(watchOS)
            /// The watch's: a watch has no room for a picker over a plugin's view.
            static let platform = rows
        #else
            /// The Mac's: a window wide enough for the picker.
            static let platform = picker
        #endif
    }

    extension EnvironmentValues {
        /// The layout of the app's screen the view is in, so its bars and a pushed plugin fit it:
        /// a list insets its rows itself, and a pushed plugin's title is the navigation title.
        @Entry var sidecarPluginLayout = SidecarPluginLayout.picker
    }
#endif
