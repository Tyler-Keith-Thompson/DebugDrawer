#if DEBUG
    import Combine
    import Foundation

    // MARK: - Badges and toasts

    public extension DebugDrawer {
        /// How long a toast stays up after its last post, in seconds, while the pointer isn't over
        /// it and accessibility focus isn't on it.
        static let toastLifetime: TimeInterval = 6

        /// Shows `count` on the plugin's section header; zero or less clears it. While the plugin's
        /// notices are silenced (``setNoticesMuted(_:forPlugin:)``) it shows nothing.
        ///
        /// - Parameters:
        ///   - count: The number to show.
        ///   - id: The plugin's ``DebugDrawerPlugin/id``.
        func setBadge(_ count: Int, forPlugin id: String) {
            if count > 0, !isNoticesMuted(forPlugin: id) {
                badges[id] = count
            } else {
                badges.removeValue(forKey: id)
            }
        }

        /// Raises a toast for the plugin while the drawer is closed. A post from the plugin that
        /// already has the toast replaces its message and adds to its count, so a burst shows as
        /// one toast; a post from another plugin replaces the toast. While the drawer is open the
        /// post is dropped: the drawer is on screen, and a badge is the lasting signal. A post from
        /// a plugin whose notices are silenced (``setNoticesMuted(_:forPlugin:)``) is dropped too.
        ///
        /// The toast goes away by itself ``toastLifetime`` seconds after its last post; each post
        /// starts the countdown again. It stays while the pointer is over it or accessibility
        /// focus is on it, and the countdown starts again once they leave.
        ///
        /// - Parameters:
        ///   - message: What the toast says.
        ///   - id: The posting plugin's ``DebugDrawerPlugin/id``.
        func postToast(_ message: String, fromPlugin id: String) {
            guard !isOpen, !isNoticesMuted(forPlugin: id) else { return }
            let count = toast.map { $0.pluginID == id ? $0.count + 1 : 1 } ?? 1
            toast = DebugDrawerToast(pluginID: id, message: message, count: count)
        }

        /// Removes the toast without opening the drawer.
        func dismissToast() {
            toast = nil
        }

        /// Opens the drawer at the toast's plugin, expanded and scrolled into view, and removes the toast.
        func openToast() {
            guard let toast else { return }
            self.toast = nil
            revealRequest = toast.pluginID
            if !isOpen { toggle() }
        }

        /// Silences or allows a plugin's badges and toasts, and saves the choice across launches.
        ///
        /// While a plugin is silenced, its ``DebugDrawerPlugin/setBadge(_:)`` shows nothing and its
        /// ``DebugDrawerPlugin/postToast(_:)`` raises nothing. Silencing it also removes the badge
        /// and toast it already shows. Allowing it again shows the badges and toasts it posts from
        /// then on; what it posted while silenced is gone. Each section header's context menu offers
        /// this as Silence Notices and Allow Notices.
        ///
        /// - Parameters:
        ///   - isMuted: Whether to silence the plugin's notices.
        ///   - id: The plugin's ``DebugDrawerPlugin/id``.
        func setNoticesMuted(_ isMuted: Bool, forPlugin id: String) {
            guard isMuted != isNoticesMuted(forPlugin: id) else { return }
            if isMuted {
                noticesMutedPlugins.insert(id)
                setBadge(0, forPlugin: id)
                if toast?.pluginID == id { dismissToast() }
            } else {
                noticesMutedPlugins.remove(id)
            }
            // Sorted, so the saved value doesn't change with the set's order.
            defaults.set(noticesMutedPlugins.sorted(), forKey: Self.noticesMutedDefaultsKey)
        }

        /// Whether the plugin's badges and toasts are silenced.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        /// - Returns: `true` from ``setNoticesMuted(_:forPlugin:)`` with `true` until it is called
        ///   with `false`, across launches.
        func isNoticesMuted(forPlugin id: String) -> Bool {
            noticesMutedPlugins.contains(id)
        }
    }

    extension DebugDrawer {
        /// Starts or ends a hold on the toast. While any hold lasts the toast stays; as the last
        /// ends, its countdown of ``toastLifetime`` starts again.
        ///
        /// - Parameters:
        ///   - isHeld: Whether the hold starts or ends.
        ///   - hold: What holds the toast.
        func setToastHeld(_ isHeld: Bool, by hold: DrawerToastHold) {
            var holds = toastHolds.value
            let changed = isHeld ? holds.insert(hold).inserted : holds.remove(hold) != nil
            // Only a change is sent: a repeated release would restart the countdown.
            if changed { toastHolds.send(holds) }
        }

        /// Removes the toast ``toastLifetime`` after the last change to it, unless a hold lasts
        /// through then.
        ///
        /// Every post changes the toast (its count, or its plugin), so each restarts the
        /// debounce. A hold sends `nil`, which removes nothing when it comes due; the hold's
        /// release sends the toast again, starting a new countdown.
        ///
        /// - Parameter scheduler: Where the countdown runs; its actions must run on the main
        ///   thread.
        /// - Returns: The subscription, which the drawer holds for its life.
        func expireToasts(on scheduler: some Scheduler) -> AnyCancellable {
            $toast.combineLatest(toastHolds)
                .map { toast, holds in holds.isEmpty ? toast : nil }
                .debounce(for: .seconds(Self.toastLifetime), scheduler: scheduler)
                .sink { [weak self] expired in
                    MainActor.assumeIsolated {
                        // The toast may have changed since: dismissed, opened, or replaced by a
                        // post the debounce hasn't seen yet.
                        guard let self, let expired, self.toast == expired else { return }
                        self.toast = nil
                    }
                }
        }

        /// A plugin the key window's drawer should show the next time it can.
        var revealRequest: String? {
            get { keyPresentation.revealRequest }
            set { keyPresentation.revealRequest = newValue }
        }

        /// The `UserDefaults` key the silenced plugins' IDs are saved under.
        static let noticesMutedDefaultsKey = "com.debugdrawer.noticesMuted"
    }
#else
    import Foundation

    public extension DebugDrawer {
        /// How long a toast would stay up after its last post, in seconds; release builds raise
        /// no toasts.
        static let toastLifetime: TimeInterval = 6

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - count: Ignored.
        ///   - id: Ignored.
        func setBadge(_ count: Int, forPlugin id: String) {}

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - message: Ignored.
        ///   - id: Ignored.
        func postToast(_ message: String, fromPlugin id: String) {}

        /// Does nothing.
        func dismissToast() {}

        /// Does nothing.
        func openToast() {}

        /// Does nothing: release builds have no badges or toasts to silence.
        ///
        /// - Parameters:
        ///   - isMuted: Ignored.
        ///   - id: Ignored.
        func setNoticesMuted(_ isMuted: Bool, forPlugin id: String) {}

        /// Always false: release builds have no badges or toasts to silence.
        ///
        /// - Parameter id: Ignored.
        /// - Returns: `false`.
        func isNoticesMuted(forPlugin id: String) -> Bool {
            false
        }
    }
#endif
