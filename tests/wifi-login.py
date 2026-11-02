#!/usr/bin/env python3
"""Unit checks for bin/wifi-login that need no network: the watcher's decisions and the uplink lookup.

  python3 tests/wifi-login.py
"""
import importlib.machinery
import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parent.parent / "bin" / "wifi-login"
loader = importlib.machinery.SourceFileLoader("wifi_login", str(path))
spec = importlib.util.spec_from_loader("wifi_login", loader)
w = importlib.util.module_from_spec(spec)
loader.exec_module(w)

ROUTES = """default via 10.0.0.1 dev usb0 proto dhcp src 10.0.0.2 metric 100
default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.5 metric 600
default dev tailscale0 scope link
"""


class Step(unittest.TestCase):
    def test_portal_opens_once(self):
        self.assertEqual(w.step(None, "portal", None), ("portal", "open"))
        self.assertEqual(w.step("portal", "portal", None), ("portal", None))

    def test_quiet_while_internet_works_elsewhere(self):
        # the bug: tethering had internet, yet the campus WiFi kept opening its login page and notifying
        for prev in (None, "portal", "skip", "dead", "dead?", "blocked"):
            self.assertEqual(w.step(prev, "portal", "usb0"), ("skip", None))
            self.assertEqual(w.step(prev, "dead", "usb0"), ("skip", None))

    def test_login_page_opens_when_tethering_goes(self):
        self.assertEqual(w.step("skip", "portal", None), ("portal", "open"))

    def test_dead_needs_two_checks(self):
        self.assertEqual(w.step(None, "dead", None), ("dead?", None))
        self.assertEqual(w.step("dead?", "dead", None), ("dead", "dead"))
        self.assertEqual(w.step("dead", "dead", None), ("dead", None))

    def test_online_after_login(self):
        self.assertEqual(w.step("portal", "online", None), ("online", "online"))
        self.assertEqual(w.step("skip", "online", None), ("online", None))


class Uplink(unittest.TestCase):
    def setUp(self):
        self.saved = w.run, w.dev_addr, w.check
        w.run = lambda *cmd: ROUTES if cmd[:2] == ("ip", "-4") else ""
        w.dev_addr = lambda dev: ("10.0.0.2", None)

    def tearDown(self):
        w.run, w.dev_addr, w.check = self.saved

    def test_route_devices_skip_tailscale(self):
        self.assertEqual(w.default_route_devs(), ["usb0", "wlan0"])

    def test_tethering_with_internet(self):
        w.check = lambda dev, ip, dns: ("online", None) if dev == "usb0" else ("portal", "http://login")
        self.assertEqual(w.internet_via(), "usb0")

    def test_only_a_portal(self):
        w.check = lambda dev, ip, dns: ("dead", None) if dev == "usb0" else ("portal", "http://login")
        self.assertIsNone(w.internet_via())

    def test_other_uplink(self):
        self.assertEqual(w.other_uplink("wlan0"), "usb0")
        self.assertIsNone(w.other_uplink("usb0"))


class LoginUrl(unittest.TestCase):
    def test_redirect_and_meta_refresh(self):
        probe = "http://detectportal.firefox.com/success.txt"
        self.assertEqual(w.login_url_from(probe, 302, "https://wifi.example/login", ""), "https://wifi.example/login")
        body = '<meta http-equiv="refresh" content="0; url=http://10.5.50.1/login?dst=x">'
        self.assertEqual(w.login_url_from(probe, 200, "", body), "http://10.5.50.1/login?dst=x")


if __name__ == "__main__":
    unittest.main(verbosity=2)
