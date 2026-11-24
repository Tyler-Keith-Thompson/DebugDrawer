# WebSocket Frames

See the frames each WebSocket connection sent and received.

## Overview

`URLSessionWebSocketTask` traffic never passes through a URL protocol, so `installNetwork()` also
records it on the tasks themselves. Each task a session makes from then on is a connection in the
WebSockets section, under the request log. Its row shows WS, whether it is open, closed or failed,
its path and how many frames it carried.

### Connection detail

A connection's detail shows when it opened and the subprotocols offered. It shows who closed it,
with which close code and reason (from `cancel(with:reason:)`, or the server's close frame), or
the error it failed with. Then come its frames, the latest first: ↑ for sent, ↓ for received, the
time to the millisecond, the kind and size, and a preview. The preview is the start of a text
frame, or the first 16 bytes of a binary one in hex (`00 01 02 … 0f …`). Pings and their pongs are
listed too.

The async and completion-handler forms of `send` and `receive` are both recorded, and the app gets
exactly the messages and errors it would get without the plugin.

### Limits and redaction

A connection keeps its latest 500 frames, and the log its latest 50 connections. Each frame keeps
its first 16 KB.

Copy Frames and the HAR export (Chrome DevTools' `_webSocketMessages`) mask the URL's query items
and JSON text frames as the redaction rules say. A text frame larger than 16 KB is copied and
exported without its text, which can't be masked.

There is nothing to install beyond `installNetwork()`. Socket libraries that don't use
`URLSessionWebSocketTask` aren't seen.
