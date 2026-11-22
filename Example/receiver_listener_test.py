"""The production host opens no network listener (DD-107, the device-lab bridge).

A device's sidecar relays a production app to a Mac viewer, so the app itself never listens: the
network transport (DebugDrawerRemote, the one module that imports Network.framework) is never in
what the production host links, which scripts/modules.py also asserts of the module graph. This
checks the built binary: the macOS production host, Example/Receiver, loads no Network.framework
and holds no NWListener or nw_listener symbol, while the macOS sidecar, which links the relay, holds
both, so the scan is shown to find them. Run in debug only: in release the sidecar kit's relay is a
stand-in that links no listener, so the control would hold none.
"""

import pathlib
import unittest
import zipfile

NETWORK_FRAMEWORK = b"/System/Library/Frameworks/Network.framework/"
LISTENER_SYMBOLS = [b"NWListener", b"nw_listener"]


def executable(app_zip):
    """The bytes of the main executable in a macos_application's zip."""
    with zipfile.ZipFile(app_zip) as bundle:
        names = [n for n in bundle.namelist() if "/Contents/MacOS/" in n and not n.endswith("/")]
        if len(names) != 1:
            raise AssertionError(f"{app_zip} holds {len(names)} executables in Contents/MacOS, not one: {names}")
        return bundle.read(names[0])


class ReceiverOpensNoListenerTest(unittest.TestCase):
    def test_the_production_host_links_no_network_framework_and_no_listener(self):
        binary = executable(pathlib.Path("Example/ExampleApp_Receiver_macOS.zip"))

        self.assertNotIn(NETWORK_FRAMEWORK, binary)
        for symbol in LISTENER_SYMBOLS:
            self.assertNotIn(symbol, binary)

    def test_the_sidecar_which_relays_links_both_so_the_scan_finds_them(self):
        binary = executable(pathlib.Path("Example/ExampleApp_Sidecar_macOS.zip"))

        self.assertIn(NETWORK_FRAMEWORK, binary)
        self.assertTrue(any(symbol in binary for symbol in LISTENER_SYMBOLS))


if __name__ == "__main__":
    unittest.main()
