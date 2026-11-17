# Contributing to Bug Reports

Add a plugin's data to the zip the drawer's Create Report button writes, masked by the drawer's
redaction rules, and send finished reports to your team.

## Overview

The drawer's header has a Create Report button. It asks every registered plugin that adopts
``DebugDrawerReportContributor`` for its files and zips them with a `summary.txt` (the app, its
version, the OS, the device model, the date and the list of files), one folder per plugin, named
after its title. Every file is plain text, JSON, an HTTP Archive, a PNG or a QuickTime movie, so
the report opens without DebugDrawer.

### Contribute a plugin's files

Adopt ``DebugDrawerReportContributor`` beside ``DebugDrawerPlugin`` and add files to the
``DebugDrawerReport`` you are handed. Pass anything that may hold a credential through the
``DebugDrawerRedaction`` you are handed with it:

```swift
struct CartPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
    var title = "Cart"
    var icon = "cart"

    var body: some View {
        Text("2 items")
    }

    func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        report.add(text: "2 items", named: "cart.txt")
        let checkout = Data(#"{"card":"4111","token":"t0k3n"}"#.utf8)
        report.add(jsonData: redaction.redacting(json: checkout), named: "checkout.json")
    }
}

#if DEBUG
DebugDrawer.shared.registerGlobal(CartPlugin())
let zip = try DebugDrawer.shared.createReport() // the same zip the button makes
#endif
```

A file's name is made safe for a file system, given its kind's extension when it lacks one, and
made unique within the plugin's folder. ``DebugDrawer/DebugDrawer/createReport(in:)`` writes the
same zip the button does, for a test or a trigger of the app's own.

### Redaction

The drawer's rules, ``DebugDrawer/DebugDrawer/redaction``, start as
``DebugDrawerRedaction/standard``: the `Authorization`, `Proxy-Authorization`, `Cookie` and
`Set-Cookie` headers, and keys containing `token`, `secret`, `password`, `session`, `auth` or an
API key's name. Add the app's own with ``DebugDrawer/DebugDrawer/redact(headers:keys:jsonPaths:)``:

```swift
#if DEBUG
DebugDrawer.shared.redact(
    headers: ["X-Api-Signature"],
    keys: ["pin"],
    jsonPaths: ["user.ssn", "cards.number"]
)
#endif
```

The same rules mask values in the shipped plugins' copy buttons, and on screen until revealed.

### Send reports to your team

Until the app sets an uploader, a report stays on the device and the library makes no network
request. Assign a ``DebugDrawerReportUploader`` to
``DebugDrawer/DebugDrawer/reportUploader`` and the drawer shows Send Report beside each finished
report, the upload's progress, and the uploader's error with a Retry button:

```swift
struct TeamReportUploader: DebugDrawerReportUploader {
    let endpoint: URL

    func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: archive)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        progress(1)
    }
}

#if DEBUG
DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)
#endif
```

The contributor and uploader protocols, ``DebugDrawerReport`` and ``DebugDrawerRedaction`` exist
in every build, so these conformances compile in release, where there is no drawer and nothing
calls them.
