# What the Network Log Captures

Which requests the Network plugin sees, how it sends them, and what it can't capture.

## Overview

`installNetwork()` registers a URL protocol for `URLSession.shared` and adds it to every
`URLSessionConfiguration`. So the log shows the http and https requests of the shared session and
of the app's other sessions, including those of networking libraries built on `URLSession`.

### How a captured request is sent

The plugin sends each request it captures on a session of its own, made from a copy of the app
session's configuration, and hands what it hears back to the app's task. The request gets the app
session's cookie storage, cache, credentials, extra headers, timeouts, proxy and TLS settings, and
an ephemeral session's cookies and cached responses stay its own.

Redirects and authentication challenges go to the app's task, so the app's session delegate
decides them as it would without the plugin. A redirect it refuses isn't followed. A delegate that
pins certificates or answers with a client certificate gets the server's challenge, and its answer
is used (see <doc:AppsThatPinCertificates>). The request goes out as the app made it, with no
header added. A body the app streams is sent with its length (`Content-Length`) instead of in
chunks.

### What isn't captured

Some requests the plugin doesn't capture, or can't keep as they were:

- Requests that don't go through a URL protocol aren't seen: background sessions' (the system
  loads them outside the app), web views' (`WKWebView`), AVFoundation's streaming (`AVPlayer`),
  Network.framework's connections and `URLSession` stream tasks. WebSocket tasks don't go through
  it either; their frames are recorded on the tasks themselves (see <doc:WebSocketFrames>).
- Requests to a host `installNetwork(bypassing:)` names aren't seen (see
  <doc:AppsThatPinCertificates>).
- A session made before `installNetwork()` is captured, but the plugin can't learn its
  configuration, so its requests are sent with the default one: the shared cookie storage, cache
  and credentials. Install at startup.
- The app's session delegate isn't told about upload progress (`didSendBodyData`) or about waiting
  for connectivity, because a URL protocol has no way to report either.

### Limits

The log keeps the newest 200 requests; set `NetworkStore.shared.capacity` for another number. It
keeps the first megabyte of each request and response body, and marks a longer body truncated with
its full size. `installNetwork(bodyLimit:)` takes another limit. The server and the app always get
the whole body.
