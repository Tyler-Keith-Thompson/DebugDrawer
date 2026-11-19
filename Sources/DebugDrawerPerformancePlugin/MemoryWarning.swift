// UIKit's platforms only. macOS has no memory warning notification and no public way to simulate
// memory pressure, so the Mac builds none of this. Mac Catalyst is os(iOS) and has
// UIApplication's notification, which its apps observe as on iOS, so it gets the button too.
#if DEBUG && (os(iOS) || os(tvOS) || os(visionOS))
    import DebugDrawer
    import SwiftUI
    import UIKit

    /// Posts the memory warning notification as the system would, to the app's observers.
    struct MemoryWarningSimulator {
        /// Where the notification goes; the app's default center unless a test passes its own.
        var center: NotificationCenter = .default

        /// Posts `UIApplication.didReceiveMemoryWarningNotification`, from the shared
        /// application as the system's comes, and returns when it was posted.
        ///
        /// Only observers of the notification receive it. The system's own memory handling, such
        /// as view controllers' `didReceiveMemoryWarning()`, doesn't run.
        @MainActor
        @discardableResult
        func post(at now: Date = Date()) -> Date {
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            return now
        }
    }

    /// The model's real way to post the warning.
    extension MemoryWarningSimulator: MemoryWarningPoster {
        @MainActor func postMemoryWarning() -> Date {
            post()
        }
    }

    /// The memory warning action, and when it was last posted.
    struct MemoryWarningSection: View {
        /// Posts the warning and returns when.
        let post: @MainActor () -> Date
        @State var postedAt: Date?
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        let inspection = Inspection<Self>()

        /// - Parameters:
        ///   - postedAt: When the warning was last posted, `nil` for not yet.
        ///   - post: Posts the warning and returns when.
        init(postedAt: Date? = nil, post: @escaping @MainActor () -> Date) {
            _postedAt = State(initialValue: postedAt)
            self.post = post
        }

        var body: some View {
            DebugDrawerSection("Memory warning") {
                DebugDrawerActionRow {
                    Button("Simulate Memory Warning") { postedAt = post() }
                        .accessibilityLabel("Simulate memory warning")
                }
                if let postedAt {
                    Text("Posted at \(postedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: locale, timeZone: timeZone)))")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .debugDrawerRowPadding()
                }
            } footer: {
                Text("Posts didReceiveMemoryWarningNotification. Only the app's observers of it receive it.")
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    }
#endif
