# Ignored Hosts and GraphQL

Hide noisy hosts from the log, and name each GraphQL request by its operation.

## Overview

Analytics and image-CDN requests can bury an app's own API calls, so the log can ignore hosts.

### Ignoring a host

A request's detail offers Ignore and its host. For a host with parent domains it offers a menu of
each (`cdn.img.example.com`, `img.example.com`, `example.com`). The Ignored hosts section, at the
bottom, lists them with Remove and takes one typed in: a host, `host:port`, an IP address or a URL,
of which only the host is kept. A `*` is refused, since a domain already covers its subdomains.

A domain hides its own requests and its subdomains', matched on whole labels and ignoring case.
So `example.com` hides `cdn.example.com` but not `badexample.com`. An IP address hides only
itself.

Ignored requests and WebSocket connections are only left out of the list, in Captured, Previous
and Imported alike. They are still captured, written to the session and put in the bug report. A
note under the log says how many are hidden ("12 hidden by ignore list"), with Show, which lists
them until Hide. Export Shown exports what the list shows.

The list is kept in `ignored.json` beside the mock rules and loaded by `installNetwork()`.
`installNetwork(ignoring:)` adds hosts of the app's own choosing, such as
`["analytics.example.com"]`, at each launch. To keep the plugin out of a host's requests entirely
instead of hiding them, see <doc:AppsThatPinCertificates>.

### GraphQL operation names

Every GraphQL request has the same path, so the log names its operation: `GetUser` on a line of
its own under the row's method and path, and Operation in the detail. The filter text matches it.

The name is a POST's JSON `operationName`, or else the first named `query`, `mutation` or
`subscription` in its `query`, past comments and fragments. A batch shows its first two names and
how many more (`GetUser, GetPosts +1`). A GET, as a persisted query sends, is named by its
`operationName` parameter. An anonymous operation, a body that isn't JSON, and a body over 1 MB
show no name.

There is nothing to install beyond `installNetwork()`.
