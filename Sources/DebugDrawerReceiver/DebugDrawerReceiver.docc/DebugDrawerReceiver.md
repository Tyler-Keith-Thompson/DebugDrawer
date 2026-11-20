# ``DebugDrawerReceiver``

The part of DebugDrawer a release build links: it serves an employee-only sidecar app the
capabilities the host enables, within sessions the sidecar opens, and refuses everything else.

## Overview

A release build gets none of the drawer. A production app that wants its employees to reach it
from a sidecar app links this module, makes a ``DebugDrawerReceiver`` over the app group's store,
enables the capabilities it offers, and starts it. The receiver has no UI and intercepts nothing;
it decodes each command into the capability's own type and runs nothing it receives.

Read <doc:SecurityModel> before enabling a capability in a build that ships: it says what the
receiver trusts, what someone holding the sidecar can do with each capability, and how to
distribute the sidecar so it stays with your employees.

## Topics

### Essentials

- <doc:SecurityModel>
- ``DebugDrawerReceiver``
- ``DebugDrawerReceiverCapability``
- ``DebugDrawerSessions``
