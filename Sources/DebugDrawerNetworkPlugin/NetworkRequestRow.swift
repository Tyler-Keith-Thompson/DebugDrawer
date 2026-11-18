#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A request's method, status, path and duration, after an error glyph when it failed, and a
    /// GraphQL request's operation below them; selected, it shows the request's detail.
    struct NetworkRequestRow: View {
        let entry: NetworkEntry
        let redaction: DebugDrawerRedaction
        let isSelected: Bool
        let onSelect: () -> Void
        /// Opens a new mock made from the request; `nil` offers no Mock This.
        var onMock: ((NetworkEntry) -> Void)?
        /// Sends the request again, unchanged; `nil` offers no Resend.
        var onResend: ((NetworkEntry) -> Void)?
        /// Opens the request in the resend editor; `nil` offers no Edit and Resend.
        var onEditAndResend: ((NetworkEntry) -> Void)?
        /// Selects the request with the id, for the links to a replay's original and its replays.
        var onShow: ((NetworkEntry.ID) -> Void)?
        /// The requests this one is linked to by replay.
        var links = NetworkReplayLinks.none
        /// Where the last resend of this request stands, if one hasn't got its answer.
        var replayStatus: NetworkReplayStatus?
        /// Adds the request's host, or a parent domain, to the ignore list; `nil` offers no Ignore.
        var onIgnore: ((NetworkIgnoredDomain) -> Void)?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        /// The least width the path gets beside the method, status and badges: about twenty
        /// characters, so it wraps at whole path segments rather than a letter or two a line.
        @ScaledMetric(relativeTo: .body) private var minimumPathWidth: CGFloat = 140

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 1) {
                        summary
                        // Every GraphQL request has the same path, so its operation names it, on
                        // a line of its own: beside the method, status and badges it would get a
                        // few letters' width in an iPad's drawer and lose its middle.
                        if let operation = entry.graphQLOperationName {
                            HStack(alignment: .firstTextBaseline) {
                                glyph.hidden()
                                Text(operation)
                                    .debugDrawerFont(.code)
                                    .debugDrawerForegroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .debugDrawerRowPadding()
                    .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if isSelected {
                    NetworkRequestDetail(
                        entry: entry, redaction: redaction, onMock: onMock, onResend: onResend, onEditAndResend: onEditAndResend,
                        onShow: onShow, links: links, replayStatus: replayStatus, onIgnore: onIgnore
                    )
                }
            }
        }

        /// The error glyph for a failed request; for any other, the same space left empty (or a
        /// spinner while it runs), so methods line up from row to row.
        private var glyph: some View {
            DebugDrawerIssueGlyph(.error)
                .opacity(entry.isFailure ? 1 : 0)
                .accessibilityHidden(!entry.isFailure)
                .overlay {
                    if !entry.isComplete {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("In progress")
                    }
                }
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.15 }
        }

        /// The method, status, badges, path and duration: on one line while the path keeps
        /// `minimumPathWidth` beside the rest; otherwise the path takes a line of its own, then
        /// the badges too when they don't fit beside the method and status.
        @ViewBuilder private var summary: some View {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility text sizes the path and the duration have no room beside the
                // method and status, so each takes a line of its own.
                VStack(alignment: .leading, spacing: 1) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline) {
                            glyph
                            method
                            status
                        }
                        if badgeCount > 0 {
                            HStack { badges }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    path
                        .frame(maxWidth: .infinity, alignment: .leading)
                    duration
                }
            } else {
                // Each candidate states the width it needs (the path's minimum beside the rest,
                // nothing on a line of its own), so the row stacks when space runs out rather
                // than squeeze the path; dropping badges instead would hide what the drawer did
                // to the request.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline) {
                            glyph
                            method
                            status
                            badges
                        }
                        // A few short words that never wrap: the path gives way to them instead.
                        .fixedSize(horizontal: true, vertical: false)
                        path
                            .frame(minWidth: minimumPathWidth, idealWidth: minimumPathWidth, maxWidth: .infinity, alignment: .leading)
                        duration
                    }
                    stacked(badgesOnOwnLine: false)
                    stacked(badgesOnOwnLine: true)
                }
            }
        }

        /// The method, status and duration on the first line, the badges beside them or on the
        /// next, and the path on a line of its own, each lined up after the glyph.
        private func stacked(badgesOnOwnLine: Bool) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    glyph
                    method
                    status
                    if !badgesOnOwnLine {
                        badges
                    }
                    Spacer(minLength: 0)
                    duration
                }
                if badgesOnOwnLine, badgeCount > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        glyph.hidden()
                        badges
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    glyph.hidden()
                    // No ideal width: on a line of its own the path takes whatever the row has.
                    path
                        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        private var badgeCount: Int {
            [entry.replayOf != nil, entry.mockRuleName != nil, entry.conditionEffect != nil].count(where: \.self)
        }

        /// Replay, Mocked and Conditioned, for a request the drawer resent, a mock answered or a
        /// profile conditioned.
        @ViewBuilder private var badges: some View {
            if entry.replayOf != nil {
                NetworkReplayBadge()
            }
            if entry.mockRuleName != nil {
                NetworkMockedBadge()
            }
            if entry.conditionEffect != nil {
                NetworkConditionedBadge()
            }
        }

        private var method: some View {
            Text(entry.method)
                .debugDrawerFont(.code)
                .debugDrawerForegroundStyle(.secondary)
        }

        private var path: some View {
            Text(entry.path)
                .debugDrawerFont(.code)
                .debugDrawerForegroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.middle)
        }

        @ViewBuilder private var status: some View {
            if let code = entry.statusCode {
                Text(String(code))
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(entry.isFailure ? .error : .primary)
            } else if entry.isComplete {
                Text("ERR")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.error)
            }
        }

        private var duration: some View {
            Text(entry.durationLabel)
                .debugDrawerFont(.value)
                .debugDrawerForegroundStyle(.tertiary)
        }
    }
#endif
