#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The URLs opened and the activities continued before, each a button that puts it back in
    /// the form, and Clear History; nothing while both are empty.
    struct DeepLinkHistoryList: View {
        /// URLs opened before, most recent first.
        let history: [String]
        /// Activities continued before, most recent first.
        let activities: [DeepLinkActivity]
        let onUseURL: (String) -> Void
        let onUseActivity: (DeepLinkActivity) -> Void
        let onClear: () -> Void

        var body: some View {
            if !history.isEmpty {
                historySection
            }
            if !activities.isEmpty {
                activitiesSection
            }
            if !history.isEmpty || !activities.isEmpty {
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Clear History", role: .destructive, action: onClear)
                        .debugDrawerButtonStyle(.destructive)
                }
            }
        }

        private var historySection: some View {
            DebugDrawerSection("History (\(history.count))") {
                ForEach(history, id: \.self) { entry in
                    Button {
                        onUseURL(entry)
                    } label: {
                        Text(entry)
                            .debugDrawerFont(.code)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityHint("Puts the URL in the field")
                }
            }
        }

        private var activitiesSection: some View {
            DebugDrawerSection("Activities (\(activities.count))") {
                ForEach(activities, id: \.self) { activity in
                    Button {
                        onUseActivity(activity)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activity.isUniversalLink ? "Universal Link" : activity.activityType)
                                .debugDrawerFont(.label)
                                .debugDrawerForegroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text(activity.summary)
                                .debugDrawerFont(.code)
                                .lineLimit(3)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                        .accessibilityElement(children: .combine)
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityHint("Puts the activity in the form")
                }
            }
        }
    }

    extension DeepLinkActivity {
        /// The second line of its history row: a universal link's URL, or the userInfo.
        fileprivate var summary: String {
            if let webpageURL {
                return webpageURL.absoluteString
            }
            return userInfo.isEmpty ? "No userInfo" : userInfo.map { "\($0.key) = \($0.value.text)" }.joined(separator: ", ")
        }
    }
#endif
