#if DEBUG
    import Foundation
    import ObjectiveC
    import os

    /// Replaces `Bundle`'s public string lookups with ones that record untranslated keys and apply
    /// the mode to the app's bundles.
    ///
    /// Two lookups are replaced, both public (`NSBundle.h`):
    /// `localizedStringForKey:value:table:`, which `NSLocalizedString`,
    /// `Bundle.localizedString(forKey:value:table:)` and the code built on them call, and
    /// `localizedStringForKey:value:table:localizations:` (macOS 15.4, iOS 18.4 and later).
    /// SwiftUI's `Text` and `String(localized:)` look strings up through Foundation's private
    /// methods instead, which the drawer doesn't replace: private API is out of bounds even in a
    /// debug build.
    ///
    /// A lookup in a bundle that isn't the app's (``AppBundles``) returns what Foundation returns,
    /// untouched and unrecorded.
    enum LocalizationInterception {
        // Behind a lock rather than main-actor state: lookups read it on whatever thread they
        // run, synchronously.
        /// Whether the replaced lookups apply the mode and record; until ``install()`` and after
        /// ``uninstall()``, one other code replaced again since, which stays in place, calls
        /// straight through to Foundation's.
        private static let isIntercepting = OSAllocatedUnfairLock(initialState: false)
        @MainActor private static let replacements = MethodReplacements()

        /// Replaces the lookups, unless they are replaced already, and starts intercepting.
        @MainActor static func install() {
            isIntercepting.withLock { $0 = true }
            replaceLookup()
            replaceLocalizationsLookup()
        }

        /// Stops intercepting and puts Foundation's lookups back, but for one other code replaced
        /// again since, under which the drawer's calls straight through. Calling it again does
        /// nothing.
        @MainActor static func uninstall() {
            isIntercepting.withLock { $0 = false }
            replacements.restore()
        }

        /// What a lookup that returned `result` returns once `mode` applies, for a key that isn't
        /// a plural: as it is, its key, or pseudo-localized.
        static func rewrite(_ result: String, key: String, mode: Localization.Mode) -> String {
            switch mode {
            case .standard:
                result
            case .showingKeys:
                key.isEmpty ? result : key
            case .pseudoLocalized:
                PseudoLocalization.transform(result)
            }
        }

        typealias Lookup = @convention(c) (Bundle, Selector, NSString?, NSString?, NSString?) -> NSString
        typealias LocalizationsLookup = @convention(c) (Bundle, Selector, NSString?, NSString?, NSString?, NSArray) -> NSString
        typealias LocalizationsReplacement = @convention(block) (Bundle, NSString?, NSString?, NSString?, NSArray) -> NSString

        @MainActor private static func replaceLookup() {
            let selector = #selector(Bundle.localizedString(forKey:value:table:))
            guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
            replacements.replace(method) { implementation in
                let original = unsafeBitCast(implementation, to: Lookup.self)
                let replacement: @convention(block) (Bundle, NSString?, NSString?, NSString?) -> NSString = { bundle, key, value, table in
                    guard isIntercepting.withLock({ $0 }) else { return original(bundle, selector, key, value, table) }
                    return outermost {
                        original(bundle, selector, key, value, table)
                    } intercept: { result in
                        intercept(BundleLookupArguments(bundle: bundle, key: key, value: value, table: table), result: result) { plurals in
                            original(plurals, selector, key, value, table)
                        }
                    }
                }
                return imp_implementationWithBlock(replacement)
            }
        }

        @MainActor private static func replaceLocalizationsLookup() {
            // Public since macOS 15.4 and iOS 18.4 (NSBundle.h), but refined for Swift, so it has no
            // #selector spelling; on an earlier system the method doesn't exist and nothing is
            // replaced.
            let selector = NSSelectorFromString("localizedStringForKey:value:table:localizations:")
            guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
            replacements.replace(method) { implementation in
                let original = unsafeBitCast(implementation, to: LocalizationsLookup.self)
                let replacement: LocalizationsReplacement = { bundle, key, value, table, localizations in
                    guard isIntercepting.withLock({ $0 }) else { return original(bundle, selector, key, value, table, localizations) }
                    return outermost {
                        original(bundle, selector, key, value, table, localizations)
                    } intercept: { result in
                        intercept(BundleLookupArguments(bundle: bundle, key: key, value: value, table: table), result: result) { plurals in
                            original(plurals, selector, key, value, table, localizations)
                        }
                    }
                }
                return imp_implementationWithBlock(replacement)
            }
        }

        /// Records an untranslated lookup of one of the app's strings and applies the mode;
        /// returns `result` as it is for any other string: one in a bundle that isn't the app's,
        /// or one whose key is in none of its tables and that passes no default value, which is
        /// SwiftUI's or the drawer's text resolved against the app's bundle (``BundleTableKeys``).
        ///
        /// - Parameter lookUpPlural: Looks the key up again in another bundle, the
        ///   pseudo-localized copy of this one's plurals.
        private static func intercept(_ arguments: BundleLookupArguments, result: NSString, lookUpPlural: (Bundle) -> NSString) -> NSString {
            let (bundle, key, value, table) = (arguments.bundle, arguments.key, arguments.value, arguments.table)
            let path = bundle.bundleURL.standardizedFileURL.path
            let state = LocalizationState.shared
            guard let key = key as String?, let mode = state.mode(forBundleAt: path) else { return result }
            let tableName = (table as String?).flatMap { $0.isEmpty ? nil : $0 } ?? LocalizationTable.defaultName
            let hasDefault = (value as String?)?.isEmpty == false
            guard hasDefault || BundleTableKeys.shared.keys(ofBundleAt: path)[tableName]?.contains(key) == true else { return result }
            if LocalizationLookup.isUntranslated(key: key, defaultValue: value as String?, result: result as String) {
                state.record(LocalizationLookup(bundlePath: path, table: table as String?, key: key, defaultValue: value as String?))
            }
            switch mode {
            case .standard:
                return result
            case .pseudoLocalized:
                // A plural is looked up again in the copy, which keeps the plural rules a string
                // built here would lose.
                if let copy = PseudoPluralBundles.shared.copy(ofBundleAt: path),
                   copy.keys[tableName]?.contains(key) == true,
                   let plurals = Bundle(url: copy.url) {
                    return lookUpPlural(plurals)
                }
                return rewrite(result as String, key: key, mode: mode) as NSString
            case .showingKeys:
                return rewrite(result as String, key: key, mode: mode) as NSString
            }
        }

        /// The key in each thread's dictionary that marks a replaced lookup in progress.
        private static let lookupInProgress = "DebugDrawerLocalizationLookupInProgress"

        /// Runs `lookup`, then `intercept` on its result; but a lookup made while another is in
        /// progress on the same thread (Foundation's methods calling each other) only runs
        /// `lookup`, so a string is recorded and rewritten once, by the outermost lookup.
        private static func outermost(_ lookup: () -> NSString, intercept: (NSString) -> NSString) -> NSString {
            let thread = Thread.current.threadDictionary
            guard thread[lookupInProgress] == nil else { return lookup() }
            thread[lookupInProgress] = true
            defer { thread.removeObject(forKey: lookupInProgress) }
            return intercept(lookup())
        }
    }

    /// The arguments of one call to a replaced lookup, except the selector and the localizations.
    private struct BundleLookupArguments {
        let bundle: Bundle
        let key: NSString?
        let value: NSString?
        let table: NSString?
    }
#endif
