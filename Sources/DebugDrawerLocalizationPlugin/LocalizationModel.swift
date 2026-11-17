#if DEBUG
    import Combine
    import Foundation

    /// The plugin's state on the main actor: the mode, the app's tables and the untranslated
    /// lookups, read again after each one the interception records.
    ///
    /// Main-actor isolated, like the drawer that shows it; the lookups it reads arrive from any
    /// thread through ``LocalizationState``.
    @MainActor
    final class LocalizationModel: ObservableObject {
        /// What the app's strings show. Setting it applies it to every lookup from then on and
        /// redraws the views under `debugLocalization()`.
        @Published var mode: Localization.Mode {
            didSet {
                guard mode != oldValue else { return }
                state.mode = mode
                onModeChange()
            }
        }

        /// The app's localized bundles, the main bundle first; empty until read.
        @Published private(set) var bundles: [LocalizedBundle] = []
        /// The keys looked up with no translation, in the order first seen.
        @Published private(set) var lookups: [LocalizationLookup] = []
        /// Foundation's own settings stored for the next launch.
        @Published private(set) var nextLaunch: Set<NextLaunchOption> = []
        /// The settings stored when the plugin was installed, at launch: what the app runs with.
        let launchedWith: Set<NextLaunchOption>

        private let source: any LocalizationTableSource
        private let state: LocalizationState
        private let onModeChange: @MainActor () -> Void
        private let nextLaunchDefaults: NextLaunchDefaults?

        /// Reads `state` now and after each lookup it records; the tables are read by
        /// ``refresh()``.
        ///
        /// - Parameters:
        ///   - source: Where the tables are read from.
        ///   - state: What the interception reads the mode from and records lookups in. Its mode
        ///     is the model's to start with.
        ///   - nextLaunchDefaults: Where the next launch's settings are stored; `nil` stores none.
        ///     What it holds now is what the app launched with.
        ///   - onModeChange: Called after each change of mode.
        init(
            source: any LocalizationTableSource,
            state: LocalizationState,
            nextLaunchDefaults: NextLaunchDefaults? = nil,
            onModeChange: @escaping @MainActor () -> Void = {}
        ) {
            self.source = source
            self.state = state
            self.nextLaunchDefaults = nextLaunchDefaults
            self.onModeChange = onModeChange
            launchedWith = nextLaunchDefaults?.stored() ?? []
            nextLaunch = launchedWith
            mode = state.mode
            state.observe { [weak self] in
                // The lookup ran on whichever thread looked it up.
                Task { @MainActor in self?.reloadLookups() }
            }
            reloadLookups()
        }

        /// Reads the tables again, off the main actor.
        func refresh() async {
            let source = source
            bundles = await Task.detached { source.bundles() }.value
            reloadLookups()
        }

        /// Stores `option` for the next launch, or removes it.
        func setNextLaunch(_ option: NextLaunchOption, isOn: Bool) {
            guard let nextLaunchDefaults else { return }
            nextLaunchDefaults.set(option, isOn: isOn)
            nextLaunch = nextLaunchDefaults.stored()
        }

        /// Whether the stored settings differ from what the app launched with, so a relaunch would
        /// change its strings.
        var isRelaunchPending: Bool {
            nextLaunch != launchedWith
        }

        /// Reads the untranslated lookups.
        func reloadLookups() {
            lookups = state.lookups
        }

        /// The translations missing for the language the app runs in.
        var currentMissing: [MissingTranslation] {
            bundles.currentLocalization.map { MissingTranslation.find(in: bundles, localization: $0, lookups: lookups) } ?? []
        }
    }
#endif
