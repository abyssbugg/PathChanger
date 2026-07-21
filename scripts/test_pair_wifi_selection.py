#!/usr/bin/env python3
"""Unit tests for pair_wifi single-device selection (PC-F-001). No network."""

from __future__ import annotations

import types
import unittest
import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "pair_wifi.py"
spec = importlib.util.spec_from_file_location("pair_wifi", SCRIPT)
pair_wifi = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pair_wifi)


def _dev(name: str):
    return types.SimpleNamespace(name=name, ips=["192.0.2.1"], port=1234)


class SelectSingleDeviceTests(unittest.TestCase):
    def test_no_devices(self):
        d, reason = pair_wifi.select_single_device([], None)
        self.assertIsNone(d)
        self.assertEqual(reason, "no_devices")

    def test_single_without_filter(self):
        d, reason = pair_wifi.select_single_device([_dev("iPhone")], None)
        self.assertEqual(d.name, "iPhone")
        self.assertIsNone(reason)

    def test_multi_without_filter_ambiguous(self):
        d, reason = pair_wifi.select_single_device([_dev("A"), _dev("B")], None)
        self.assertIsNone(d)
        self.assertEqual(reason, "ambiguous")

    def test_exact_name_match(self):
        d, reason = pair_wifi.select_single_device(
            [_dev("iPhone Alice"), _dev("iPhone Bob")], "iPhone Bob"
        )
        self.assertEqual(d.name, "iPhone Bob")
        self.assertIsNone(reason)

    def test_unique_substring(self):
        d, reason = pair_wifi.select_single_device(
            [_dev("iPhone Alice"), _dev("iPhone Bob")], "Alice"
        )
        self.assertEqual(d.name, "iPhone Alice")
        self.assertIsNone(reason)

    def test_ambiguous_substring(self):
        d, reason = pair_wifi.select_single_device(
            [_dev("iPhone Alice"), _dev("iPhone Alicia")], "Ali"
        )
        self.assertIsNone(d)
        self.assertEqual(reason, "ambiguous")

    def test_no_match(self):
        d, reason = pair_wifi.select_single_device([_dev("iPhone")], "Watch")
        self.assertIsNone(d)
        self.assertEqual(reason, "no_match")


if __name__ == "__main__":
    unittest.main()
