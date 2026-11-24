# HTTP Archives

Export the Network log as a HAR file, and open HAR files from other tools.

## Overview

The Network log exports as an HTTP Archive (HAR 1.2), the file that Charles, Proxyman and
browsers' network inspectors read.

### Export

Export All shares every request the log holds. While the status filter or the filter text hides
some, the button reads Export Shown and the file holds only the requests listed.

The file has each request's start, time, method, URL, headers, query, cookies and body, and the
response's status, headers, cookies and body (in base64 when it isn't text). It has timings where
the request was measured, and `-1` for sizes the plugin doesn't know.

The redaction rules apply as they do to Copy cURL. Headers, query items and JSON body values are
masked, and so are the cookies whose names the rules match, both in the cookie lists and in the
`Cookie` and `Set-Cookie` headers.

### Import

Import HAR… opens a `.har` or `.json` file and shows its requests in the log in place of the
captured ones, under Captured and Imported, which switch between the two. Archives from Chrome
DevTools, Charles and Proxyman read as well as the drawer's own: fields they leave out are
unknown, and fields of their own are ignored.

Imported requests are read-only. Their detail offers Copy cURL and Mock This, which makes a mock
that answers like the archive's response, but not Resend. Clear removes the imported file and
shows the captured requests again.

A file that isn't a HAR 1.x archive is refused, with the reason under the buttons ("The file isn't
JSON."), and the log stays as it was.

### Bug reports

The bug report's `network.har` holds only the captured requests and WebSocket connections. An
earlier launch's are in `network-previous.har` (see <doc:NetworkSessions>).
