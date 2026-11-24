# Contributing to Bug Reports

Add a plugin's data to the zip the drawer's Create Report button writes, masked by the drawer's
redaction rules, and send finished reports to your team.

## Overview

The drawer's header has a Create Report button. It asks every registered plugin that adopts
``DebugDrawerReportContributor`` for its files and zips them with a `summary.txt` (the app, its
version, the OS, the device model, the date and the list of files), one folder per plugin, named
after its title. Every file is plain text, JSON, an HTTP Archive, a PNG or a QuickTime movie, so
the report opens without DebugDrawer, and the redaction rules mask what they call sensitive. When
the zip is ready, the drawer shows its name and a share button.

The shipped plugins add these files:

| Plugin | Adds |
|---|---|
| Console | Its log lines, and an earlier launch's (`console-previous.txt`) |
| Network | An HTTP Archive (`network.har`) of the captured requests |
| App Info | Its facts |
| UserDefaults | The app's keys |
| Cookies | The stored cookies |
| Screenshot | The key window |
| Screen Recording | The newest recording |
| Keychain | Nothing |

A plugin that doesn't adopt ``DebugDrawerReportContributor`` is left out of the report.

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

DebugDrawer.shared.registerGlobal(CartPlugin())
let reports = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
let zip = try DebugDrawer.shared.createReport(in: reports) // the same zip the button makes
```

A file's name is made safe for a file system, given its kind's extension when it lacks one, and
made unique within the plugin's folder. ``DebugDrawer/DebugDrawer/createReport(in:)`` writes the
same zip the button does, for a test or a trigger of the app's own.

### Redaction

Network's Copy cURL, Keychain's and UserDefaults' Copy Value, Cookies' Copy and Analytics' Copy
JSON mask what the drawer's redaction rules call sensitive. The same values are masked on screen
until the eye button beside them reveals them, and revealing never changes a copy. A plugin
installed in a `DebugDrawer()` of your own masks by that drawer's rules, and Network writes its
sessions to disk by them.

The drawer's rules, ``DebugDrawer/DebugDrawer/redaction``, start as
``DebugDrawerRedaction/standard``: the `Authorization`, `Proxy-Authorization`, `Cookie` and
`Set-Cookie` headers, and keys containing `token`, `secret`, `password`, `session`, `auth` or
`apikey`. Add the app's own with one call to
``DebugDrawer/DebugDrawer/redact(headers:keys:jsonPaths:)``:

```swift
DebugDrawer.shared.redact(
    headers: ["X-Api-Signature"],
    keys: ["pin"],
    jsonPaths: ["user.ssn", "cards.number"]
)
```

Header names and key patterns match case-insensitively. A key pattern matches header names, URL
query items, JSON keys at any depth, keychain accounts, services and labels, cookie names,
`UserDefaults` keys, log lines' metadata keys and the keys of pairs in log text. A JSON path is
dot-separated keys from the root, `*` matches any one key, and arrays are transparent. Assign
`DebugDrawer.shared.redaction = .none` to mask nothing.

#### Console lines

The Console shows its lines as logged, and masks them as they leave it. Copy All, a line's Copy
Line, and the bug report's `console.txt` and `console-previous.txt` mask a metadata field whose
key matches (`token=[REDACTED]`). They also mask the value of each `key=value` or `key: value`
pair in the text whose key matches (`redacting(text:)`):

- A key is a run of letters, digits, `_`, `-` and `.` (`x-api-key`, `user.token`), or text in
  quotes, as JSON writes keys (`"access token"`).
- The separator is `=` or `:`, with spaces allowed around it; `==`, `::` and `://` aren't
  separators.
- A value in quotes is masked inside them, an escaped quote included (`"token": "[REDACTED]"`).
  Any other value runs up to the next whitespace, `&`, `,`, `;`, `)`, `]`, `}` or quote, so each
  item of a query string is read on its own (`?page=2&access_token=[REDACTED]&lang=en`). A value
  starting with `{`, `[` or `(` is left for the pairs inside it.
- Every pair is read, including a repeated key's. A value spelled with spaces outside quotes is
  masked only up to its first space.

A token written into a sentence, outside such a pair, has no key to match and stays as logged.

### Send reports to your team

To send a report straight to your team (an internal endpoint, an issue tracker's webhook), assign
a ``DebugDrawerReportUploader`` to ``DebugDrawer/DebugDrawer/reportUploader``. The uploader is
handed the zip's URL and reports the fraction sent. The drawer then shows Send Report beside each
finished report, the upload's progress, and the uploader's error with a Retry button when it
fails. The zip stays on disk until the system clears the temporary directory, so a failed upload
can be retried or the report shared instead. Until the app sets an uploader there is no send
button, a report stays on the device, and DebugDrawer itself makes no network request.

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

DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)
```

The contributor and uploader protocols, ``DebugDrawerReport`` and ``DebugDrawerRedaction`` exist
in every build, so these conformances compile in release, where there is no drawer and nothing
calls them. There ``DebugDrawer/DebugDrawer/createReport(in:)`` throws
``DebugDrawerReport/WriteFailed``.
