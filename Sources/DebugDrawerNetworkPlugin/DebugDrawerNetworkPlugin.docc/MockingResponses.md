# Mocking Responses

Answer requests with canned responses without changing the server.

## Overview

The Network plugin can answer requests itself. A mock rule matches requests by method, host, path
and query items, and answers with a status, headers and a body. A developer can use one to try an
error, an empty list, or an endpoint the server doesn't have yet. Rules are made in the drawer
(Add Mock, or Mock This on a captured request, which starts from its method, host, exact path and
the response the server sent), or passed to `installNetwork(mocks:)`:

```swift
import DebugDrawerNetworkPlugin

let outage = NetworkMockRule(
    id: UUID(uuidString: "3F2B8E1C-0D4A-4B7E-9C61-5A2D7E8F9B10")!,
    name: "Orders outage",
    matcher: .init(methods: ["GET", "POST"], host: .wildcard("*.example.com"), path: .wildcard("/v1/orders/**")),
    response: .init(status: 503, body: .text(#"{"error":"maintenance"}"#), contentType: "application/json")
)
DebugDrawer.shared.installNetwork(mocks: [outage])
```

### Matching

A host or path is matched exactly, by a wildcard, or by a regular expression
(`NSRegularExpression`). A wildcard or regex must match the whole of it. In a host, `*` matches
within one label (`*.example.com` matches `api.example.com`) and `**` across labels. In a path,
`*` matches within one segment (`/users/*`) and `**` across segments (`/users/**`). Hosts ignore
case; paths are compared percent-decoded.

The rules are tried in the order the drawer lists them. The first rule that is on and matches
answers, and no request is sent. `Content-Length` is always the body's length. A request no rule
matches reaches the network unchanged. Rules apply only once `installNetwork()` has run.

A production build gets none of this. A sidecar can set rules there for its session, through the
sessions the app configures; the DebugDrawerReceiver documentation's Mocking the Network in
Production article covers it.

### The Mocks section

The Mocks section, below the request log, lists each rule with a switch, its methods, pattern and
status. Selecting one offers Edit, Move Up, Move Down and Delete. The plugin's header counts the
rules that are on.

The editor takes the methods, the host's and path's patterns (an invalid regex says why below its
field), query items, the status, a content type, headers, and a body as text or a file. A file is
copied into the app's storage.

### Storage

A rule passed to `installNetwork(mocks:)` is added once, by its `id`, so edits made in the drawer
last. Rules are saved as JSON in Application Support, in the app's folder under
`DebugDrawer/NetworkMocks`, and loaded by `installNetwork()`.

### Mocked requests in the log

A request a rule answered shows Mocked in the log, and its detail names the rule. The bug report's
`network.har` says which rule answered it.
