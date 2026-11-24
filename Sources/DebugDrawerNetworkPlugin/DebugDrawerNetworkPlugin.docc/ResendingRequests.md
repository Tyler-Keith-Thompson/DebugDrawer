# Resending Requests

Send a captured request again, as it was or edited first.

## Overview

A captured request's detail offers Resend, which sends it again unchanged, and Edit and Resend,
which opens its method, URL, headers and body for changes first. The URL must be http or https
with a host, and a GET or HEAD can't carry a body.

A POST, PUT, PATCH, DELETE or any other method that isn't safe asks for confirmation before it is
sent, in place under the buttons. A GET, HEAD, OPTIONS or TRACE is sent at once.

The resent request goes through the plugin like any request the app makes, so a mock rule can
answer it and a conditioning profile can slow it. It uses the app's default session configuration
(its cookies and cache).

### In the log

The resent request shows in the log as a new request marked Replay. Its detail names the request
it resent ("Replay of GET /v1/greeting at 10:42:05"), with a button that selects that request. The
original says how many times it was resent. If a resend gets no answer, the original's detail says
why. `network.har` notes each replay's original.

The mark stays inside the process. No header is added, so the server sees exactly the request
shown.

There is nothing to install beyond `installNetwork()`.
