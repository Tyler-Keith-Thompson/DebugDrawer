# Recording Crashes

Record each crash as it happens, and show it the next time the app starts.

## Overview

After a crash on a test device, nothing on screen says why. Crash Reports records each crash as it
happens and shows it the next time the app starts:

```swift
import DebugDrawerCrashReportsPlugin

// At startup, after any crash SDK has installed its own handlers:
CrashReports.install()
```

`CrashReports` exists in every configuration, so the call needs no `#if DEBUG`. In release it
installs nothing.

### What is caught

In debug builds it catches uncaught Objective-C exceptions (with `NSSetUncaughtExceptionHandler`)
and the fatal signals `SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE` and `SIGTRAP`. The signals
are how Swift's runtime failures (a force unwrap of `nil`, an index out of range, `fatalError`)
arrive on arm64.

Each handler writes a short report: what crashed, when, the app's version, and the stack. For an
exception the stack is its call stack symbols; for a signal it is the crashed thread's frames,
named by `backtrace_symbols_fd`. Then the handler calls the handler that was installed before it,
so a crash SDK the app also uses still records the crash. Install after the SDK for that.

The signal handler runs on an alternate stack, the plugin's own unless the installing thread
already has one, so a stack overflow on that thread is recorded too. The `MXCrashDiagnostic`s that
MetricKit delivers, often a day later, are kept as reports as well.

### On the next launch

On the next launch the plugin keeps the report with the others: the newest ten, in the app's
Application Support directory (`install(directory:)` takes another). It puts a badge on its header
for each report not yet opened, and posts a toast for the crash it recorded itself.

The drawer lists the reports newest first. Opening one shows its stack trace, selectable, with a
button that copies the whole report, and marks it seen. Mark All Seen clears the badge. Each report
can be deleted, or all of them at once. A bug report carries every crash report as a text file.

### Exceptions on the Mac's main thread

On macOS, AppKit catches an exception raised on the main thread while it handles an event, logs
it and carries on, so no uncaught exception reaches the handler. Set the
`NSApplicationCrashOnExceptions` default to `true` to have the app crash, and be recorded,
instead.

### Production crashes

A release build installs no handlers. To get a production app's crashes, such as a dogfooder's,
let the receiver forward MetricKit's crash diagnostics to a sidecar; see the DebugDrawerReceiver documentation's
Collecting Crash Reports and MetricKit Payloads article.
