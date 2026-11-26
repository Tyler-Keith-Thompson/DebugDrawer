# Apps That Pin Certificates

What an app that pins its server's certificate can count on with the Network plugin installed,
and how to keep a host out of the plugin.

## Overview

An app whose session delegate pins its server's certificate or key can count on the following.

The app's pin decides. The plugin's session hands every TLS challenge to the app's task, so the
app's session delegate is asked about the server's trust as it would be without the plugin, and
its answer is used. The plugin never trusts a server on its own. This also holds for a session
made before `installNetwork()`: it is sent with the default configuration, but its challenges
still go to its own delegate.

A refused pin sends nothing. When the delegate cancels the challenge, the connection ends in its
TLS handshake. The request line, the headers (an `Authorization` token among them) and the body
never reach the server, and the app's task fails with `URLError(.cancelled)`, as it does without
the plugin.

A stream held open passes through. Server-Sent Events and other long responses reach the app as
they arrive, while the response is still open. The log keeps only the first `bodyLimit` bytes,
however long the stream runs.

### What the tests don't cover

ATS pinning (`NSPinnedDomains` in the app's Info.plist) isn't tested. The system reads it for
every `URLSession` in the app's process, the plugin's included, but no test shows the plugin's
requests are refused the same way. ATS reads the key from the app's own Info.plist, which a test
runner doesn't have, and it checks a pin only on top of the system's trust, which a test server's
self-signed certificate on a loopback address never gets.

Pinning libraries aren't tested either. Alamofire's `ServerTrustManager` and TrustKit's delegate
swizzling check the certificate in the session delegate, which gets the challenge as described
above, but neither library is tested here.

### Bypassing a host

To keep a host out of the plugin entirely, bypass it:

```swift
import DebugDrawerNetworkPlugin

try DebugDrawer.shared.installNetwork(bypassing: ["api.example.com"])
```

Requests to a bypassed host, and to its subdomains, never reach the plugin's URL protocol. The
app's session sends them itself, with its own delegate, as if the plugin weren't installed. They
aren't logged, mocked, conditioned or offered for resending, and their WebSocket tasks aren't
recorded. The app's other traffic is captured as usual.

A host is matched the way an ignored host is (see <doc:IgnoredHostsAndGraphQL>): on whole labels,
ignoring case, and an IP address matches only itself. Each call replaces the hosts an earlier call
bypassed. Text that isn't a host throws `NetworkPlugin.InvalidInstallation.bypassedTextNotAHost`
and installs nothing, so a typo can't leave a pinned host intercepted.
`ignoring:` only hides requests from the list; `bypassing:` keeps the plugin out of them.
