# Testing Localization

Find text that doesn't fit and strings nobody translated.

## Overview

The Localization plugin pseudo-localizes the app's strings or shows their keys while the app runs,
and lists the translations a language is missing:

```swift
import DebugDrawerLocalizationPlugin

// At startup, before the first string is looked up:
Localization.install()

// Or, for a launch argument of the app's own, starting pseudo-localized:
Localization.install(mode: ProcessInfo.processInfo.arguments.contains("-PseudoLocalize") ? .pseudoLocalized : .standard)
```

`Localization` exists in every configuration and does nothing in release, so the call needs no
`#if DEBUG`.

### Live modes

In debug builds `install()` replaces `Bundle`'s public lookup,
`localizedString(forKey:value:table:)`, which `NSLocalizedString` calls.

Pseudo-Localize turns "Settings" into "[Šéţţîñĝš····]": every letter accented, about 40% longer,
and bracketed, so clipped or concatenated text shows. Format specifiers (`%@`, `%1$lld`, `%.2f`)
are kept. A plural from a `.stringsdict` keeps its rules: each variant is rewritten and looked up
again, so "1 order" and "3 orders" still differ.

Show Keys draws each string's key in its place.

Both modes apply only to the app's own bundles (the main bundle and the bundles and frameworks
inside it), never to the drawer's or the system's, and only to strings the app's tables hold or
that pass a default value. SwiftUI's own strings that it resolves against the main bundle are left
alone.

### Whole app on next launch

SwiftUI's `Text("key")`, `String(localized:)` and `LocalizedStringResource` don't go through that
lookup, so the live modes don't reach them. For those, Whole App on Next Launch stores Foundation's
own settings in the app's defaults. Accented and Doubled sets `NSAccentuateLocalizedStrings` and
`NSDoubleLocalizedStrings`, Untranslated in Capitals sets `NSShowNonLocalizedStrings`, and turning
one off removes its keys. Foundation reads them at launch, so they take effect when the app is next
launched, and they change every string, the drawer's and the system's included. Until then the
plugin shows "Relaunch to apply". Its header says "relaunch to apply" or, while the app runs with
them, "whole app", so an app that comes up accented says why.

The plugin also lists Apple's launch arguments, to copy into the scheme:
`-NSDoubleLocalizedStrings YES`, `-NSAccentuateLocalizedStrings YES`,
`-NSShowNonLocalizedStrings YES`, `-NSForceRightToLeftWritingDirection YES` and `-AppleLanguages`
with the language picked under Missing Translations (`-AppleLanguages (de)`). Show Keys has no
Foundation setting, so it is live only. Foundation's accenting marks the letters of format
specifiers too, so a string formatted from an accented format can lose its arguments
(`Delivery: @`); the live mode keeps them.

### Redrawing

Text already on screen is redrawn when the mode changes under `.debugLocalization()`, which gives
the views below it a new identity (and so resets their `@State`). Text elsewhere changes the next
time it is looked up.

### Missing translations

Missing Translations compares each language's `.strings` and `.stringsdict` tables in the app's
`.lproj` folders with the development language's (and `Base.lproj`), by table. It adds the keys the
app looked up while running and got no translation for, marked "Looked up". The list has a
language picker and a filter and copies as text or CSV. The plugin's header shows how many
translations are missing for the current language. The bug report carries `localization.txt`: the
mode, the languages and what each is missing. tvOS and watchOS have no pasteboard, so there the
plugin offers no copy.

### In production

The live modes replace `Bundle`'s lookup, which a release build never does. There a sidecar
switches the strings the app reads through `LocalizationReview` to their keys or pseudo text
instead. See the DebugDrawerReceiver documentation's Reviewing Localization in Production
article.
