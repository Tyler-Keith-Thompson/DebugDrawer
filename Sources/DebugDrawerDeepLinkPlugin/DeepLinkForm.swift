#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The mode picker over the field and its Open or Continue button, or the activity type and
    /// its userInfo; the result of the last send; the presets; and the URLs opened and the
    /// activities continued before.
    struct DeepLinkForm: View {
        /// A named example URL.
        struct Preset: Equatable {
            var label: String
            var url: String
        }

        @Binding var urlText: String
        /// What came of the last send; nil before one.
        let outcome: DeepLinkOutcome?
        let presets: [Preset]
        /// URLs opened before, most recent first.
        let history: [String]
        /// Activities continued before, most recent first.
        let activities: [DeepLinkActivity]
        let onOpen: (URL) -> Void
        let onContinue: (DeepLinkActivity) -> Void
        let onClear: () -> Void
        @State private var mode: DeepLinkMode
        @State private var draft: ActivityDraft
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let inspection = Inspection<Self>()

        /// - Parameters:
        ///   - mode: The mode to start in; by default, what the typed URL suggests.
        ///   - draft: The activity to start with in Activity mode.
        init(
            urlText: Binding<String>,
            outcome: DeepLinkOutcome? = nil,
            presets: [Preset],
            history: [String] = [],
            activities: [DeepLinkActivity] = [],
            mode: DeepLinkMode? = nil,
            draft: ActivityDraft = ActivityDraft(),
            onOpen: @escaping (URL) -> Void,
            onContinue: @escaping (DeepLinkActivity) -> Void,
            onClear: @escaping () -> Void
        ) {
            _urlText = urlText
            self.outcome = outcome
            self.presets = presets
            self.history = history
            self.activities = activities
            _mode = State(initialValue: mode ?? .suggested(for: urlText.wrappedValue))
            _draft = State(initialValue: draft)
            self.onOpen = onOpen
            self.onContinue = onContinue
            self.onClear = onClear
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection {
                    modePicker
                        .padding(.vertical, 4)
                    Group {
                        if mode == .activity {
                            activityTypeRow
                        } else {
                            urlRow
                        }
                    }
                    .padding(.vertical, 4)

                    if let outcome {
                        DebugDrawerIssueRow(outcome.text, severity: outcome.severity)
                    }
                }

                if mode == .activity {
                    DebugDrawerSection("User Info") {
                        UserInfoEditor(fields: $draft.fields)
                        if case let .invalid(problem) = draft.validation {
                            DebugDrawerIssueRow(problem, severity: .warning)
                        }
                        DebugDrawerActionRow {
                            Button("Add Key") { draft.fields.append(UserInfoField()) }
                        } trailing: {
                            EmptyView()
                        }
                    }
                } else {
                    presetsSection
                }

                DeepLinkHistoryList(
                    history: history, activities: activities, onUseURL: { use($0) }, onUseActivity: { use($0) }, onClear: onClear
                )
            }
            .onChange(of: DeepLinkMode.suggested(for: urlText)) { _, suggested in
                // Typing switches between Open URL and Universal Link as the URL becomes or stops
                // being a web URL; within one, the mode the user picked stays.
                if mode != .activity {
                    mode = suggested
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        // At accessibility text sizes the three titles don't fit side by side, so the picker is a menu.
        @ViewBuilder private var modePicker: some View {
            let picker = Picker("Send as", selection: $mode) {
                ForEach(DeepLinkMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Send as")
            if dynamicTypeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
            }
        }

        /// A field beside its button, or above it at accessibility text sizes, where the button
        /// would leave the field too little width to read.
        private var sendRowLayout: AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
        }

        private var urlRow: some View {
            sendRowLayout {
                TextField("Enter URL…", text: $urlText)
                    .debugDrawerFont(.code)
                    .debugDrawerTextFieldStyle()
                    .textContentType(.URL)
                    .accessibilityLabel(mode == .open ? "URL to open" : "Universal link")
                    #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    #endif

                Group {
                    if mode == .universalLink {
                        Button("Continue") {
                            if let url = typedURL, url.isWebURL {
                                onContinue(.universalLink(url))
                            }
                        }
                        .disabled(typedURL?.isWebURL != true)
                        .accessibilityLabel("Continue universal link")
                        .help("Continues an http or https URL in the app, as a tapped universal link")
                    } else if let url = typedURL {
                        Link("Open", destination: url)
                            .environment(\.openURL, OpenURLAction { url in
                                onOpen(url)
                                return .handled
                            })
                    } else {
                        Button("Open") {}
                            .disabled(true)
                    }
                }
                .debugDrawerButtonStyle(.primary)
                // Its ideal size: the field beside it gives up the width instead.
                .fixedSize()
            }
        }

        private var activityTypeRow: some View {
            sendRowLayout {
                TextField("Activity type", text: $draft.activityType)
                    .debugDrawerFont(.code)
                    .debugDrawerTextFieldStyle()
                    .autocorrectionDisabled()
                    .accessibilityLabel("Activity type")
                    #if os(iOS)
                        .autocapitalization(.none)
                    #endif

                Button("Continue") {
                    if let activity = draft.validation.activity {
                        onContinue(activity)
                    }
                }
                .disabled(draft.validation.activity == nil)
                .accessibilityLabel("Continue activity")
                .debugDrawerButtonStyle(.primary)
                .fixedSize()
            }
        }

        private var presetsSection: some View {
            DebugDrawerSection("Presets") {
                // At accessibility text sizes a preset's name leaves its URL too little width, so
                // the URL sits below the name.
                let presetLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout())
                ForEach(presets, id: \.url) { preset in
                    Button {
                        use(preset.url)
                    } label: {
                        presetLayout {
                            Text(preset.label)
                                .debugDrawerFont(.body)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer()
                            }
                            Text(preset.url)
                                .debugDrawerFont(.code)
                                .debugDrawerForegroundStyle(.tertiary)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                // Stacked, the URL is otherwise offered one line's height and
                                // truncates rather than wrapping.
                                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        }
                        .padding(.vertical, 3)
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityHint("Puts the URL in the field")
                }
            }
        }

        /// The typed URL, or nil while the field is empty or not a URL.
        private var typedURL: URL? {
            let trimmed = urlText.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : URL(string: trimmed)
        }

        /// Puts a preset's or an earlier URL in the field, in the mode it suggests.
        private func use(_ url: String) {
            urlText = url
            mode = .suggested(for: url)
        }

        /// Puts an earlier activity back in the form.
        private func use(_ activity: DeepLinkActivity) {
            if activity.isUniversalLink, let url = activity.webpageURL {
                urlText = url.absoluteString
                mode = .universalLink
            } else {
                draft = ActivityDraft(activity)
                mode = .activity
            }
        }
    }

    extension ActivityDraft.Validation {
        /// The activity to send, or nil while the draft can't be sent.
        fileprivate var activity: DeepLinkActivity? {
            if case let .ready(activity) = self { activity } else { nil }
        }
    }
#endif
