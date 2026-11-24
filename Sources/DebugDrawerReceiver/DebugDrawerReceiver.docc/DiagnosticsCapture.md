# Capturing Diagnostics in Production

See what a release build logs and sends while an employee reproduces a problem, redacted, for the
length of a session.

## Overview

The app hands a `DebugDrawerDiagnosticsCapture` its log lines and its requests. A sidecar that
starts the capture in its session reads them, redacted, and puts them in its bug report:

```swift
let capture = DebugDrawerDiagnosticsCapture(sessions: sessions)
receiver.enable(.diagnosticsCapture(capture))

// The app's logger's backend:
capture.log(level: .error, message: "Payment declined", metadata: ["order": "1042"], subsystem: "com.example.shop")

// The app's networking code, once it has the outcome:
let started = Date()
let (data, response) = try await session.data(for: request)
capture.record(request, response: response, body: data, started: started)
```

### The risk: real customers' data on disk

What the app logs and sends belongs to the person using it, and a capture keeps it in the app
group's container, which every app of the group can read, until it is deleted. The capture limits
that in the four ways below.

### Nothing outside a session

Until a sidecar sends `DebugDrawerDiagnosticsCapture.Command.start` in an open session (with a
grant listing the capability, under a grant policy or after `.requiringGrant()`), `log` and
`record` do nothing and evaluate none of their arguments. A session opened for anything else
captures nothing.

Nothing is ever intercepted: no os_log reading, no URL protocol, no swizzling. The app hands over
what it already has, after its own call, so a request is never sent again and nothing the app sees
changes. Until the app enables the capability, `start` is refused as
`commandRefused(.unknownCapability)`.

### Redacted, then kept

Each line and request is redacted on the calling thread before it is kept anywhere, by
`DebugDrawerDiagnosticsRedaction` (`.standard` unless the app passes its own,
`.standard.adding(headers:keys:jsonPaths:values:)`). It masks:

- the `Authorization`, `Proxy-Authorization`, `Cookie` and `Set-Cookie` headers;
- values under keys containing `token`, `secret`, `password`, `session`, `auth`, `apikey`, `email`
  or `phone`, in headers, URL query items, JSON keys at any depth, a log line's metadata, and
  `key=value` or `key: value` pairs in the message, read as the DebugDrawer
  documentation's Contributing to Bug Reports article describes;
- JSON paths the app lists;
- a URL's user and password;
- in the message, metadata values, header values, the URL's path, query and fragment and JSON
  strings, any text that is an email address, a JSON Web Token, a `Bearer` credential or a secret
  written as `password=…`.

A body is kept only when it is JSON, redacted the same way. Any other body (a form, a multipart
upload, an image) is left out with only its size. A failure keeps its error domain and code, never
its message. Subsystem and category names are kept as the app wrote them.

### Bounded

`DebugDrawerDiagnosticsCapture.Limits` (`.standard`: 1,000 lines, 200 requests, bodies up to 64
KiB, 2 MiB of text in all) drops the oldest entries first and counts what it dropped. A larger body
is left out.

### Deleted with the session

The capture lives in memory and in the capability's snapshot file in the app's own directory of the
store, nowhere else. Both are deleted as the sidecar sends `stop`, as the session ends or expires,
as a gate turns the capability off (audited as `changeReverted`), and, after a launch killed
during a session, as the next launch enables the capability, so enable it at startup.

When the sidecar makes its report it copies the capture in (`Snapshot.consoleLog`,
`Snapshot.networkJSON`) and sends `export`. The app records the export in `Snapshot.exports` (when,
how many lines and requests) and in the audit log as `commandApplied`. That copy, in the sidecar's
report, is the only one that outlives the session; the app keeps no copy for having exported it.

### Showing it

Show `capture.snapshot.isCapturing` in the app's session indicator. In the sidecar, the kit's
`DebugDrawerSidecarPlugin.diagnosticsCapture` offers Start Capture, shows the capture, and adds it
to the report.
