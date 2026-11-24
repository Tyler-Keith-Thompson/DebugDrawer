# Bug Reports from the Production App

Let employees dogfooding the build that ships file a report from the app, with a screenshot, recent
log lines and the app's state, sent through the sidecar.

## Overview

With their sidecar's session open, an employee who hits a problem triggers a report in the app. The
app takes a screenshot of its own key window, the diagnostics capture's recent lines and a state
snapshot of its choosing, and hands them to the sidecar. There the employee annotates the report and
sends it through the sidecar's uploader. The library adds no trigger: call `trigger(note:)` from one
of your own, such as a shake handler, a Feedback menu item or a button on an internal screen:

```swift
struct CheckoutState: Encodable {
    let screen: String
    let cartItems: Int
}

let reports = DebugDrawerBugReports(sessions: sessions, diagnostics: capture) {
    CheckoutState(screen: "checkout", cartItems: 2)
}
receiver.enable(.bugReports(reports))

// The app's own trigger, such as its shake handler:
reports.trigger(note: "Shaken on the checkout screen")
```

### The risk: what was on screen

A report holds what the employee had on screen, which can't be redacted. It is an image the app
draws from its own window: no screen capture, and nothing of another app or the system. The report
also holds the app's log lines and its state, which are redacted. The capability limits the risk in
the four ways below.

### Off unless enabled, and no trigger of its own

Until the app enables `.bugReports(_:)`, a trigger in a session is refused as `unknownCapability`.
Nothing in the library calls `trigger(note:)`, so without a trigger of the app's own nothing is ever
taken.

### Only in a session, through the same gates as a command

Outside a session `trigger(note:)` returns `.refused(.noActiveSession)` at once. It draws nothing,
reads no state and writes no audit entry, so a trigger left wired up for every user does nothing for
a customer. In a session, a trigger meets the receiver's and the capability's gates
(`receiverDisabled`, `capabilityDisabled`) and, under a grant policy or after `.requiringGrant()`,
needs a grant that lists `DebugDrawerBugReports.pluginID`. A report taken is audited as
`commandApplied`.

### The app never uploads

A report goes only into the capability's snapshot in the app's own directory of the store, which the
sidecar reads; the sidecar sends it. `DebugDrawerReceiver` depends on no other module, so a
production app that links it links no uploader (`DebugDrawerReportUploader` is in `DebugDrawer`,
which a release build doesn't link).

### Redacted, bounded, and deleted with the session

The note and the state (encoded as JSON) are redacted by `DebugDrawerDiagnosticsRedaction`
(`.standard` unless the app passes its own). The log lines are the diagnostics capture's, redacted
there, and are included only while a sidecar has started that capture in the session (otherwise
`logs` is `.notCapturing`); see <doc:DiagnosticsCapture>.

`DebugDrawerBugReports.Limits` (`.standard`: 3 reports, the newest 200 lines each, 64 KiB of state,
4 MiB of screenshot, drawn again at one pixel per point before it is left out) drops the oldest
report first and leaves out a larger state or screenshot with its size.

Reports are deleted as the session ends or expires (audited `changeReverted`), as a gate turns the
capability off, as the sidecar deletes one, and, after a launch killed during a session, as the next
launch enables the capability, so enable it at startup. `export(id:)` records that the sidecar took
a copy (`Snapshot.exports`, audited `commandApplied`); the app keeps no copy for it.

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.bugReports` shows each report with an annotation field and
Include in Report. Create Report puts the report picked (the newest unless another is picked) in the
zip, under `Bug Reports/` (`screenshot.png`, `note.txt` with the app's note and the annotation,
`console.txt`, `state.json`), and Send Report sends it through
`DebugDrawer.shared.reportUploader`.
