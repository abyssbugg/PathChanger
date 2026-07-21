#!/usr/bin/env python3
"""
WiFi pairing helper for PathChanger (PC-F-001: single-device only).

`pymobiledevice3 remote pair` uses a short Bonjour browse window which is
sometimes too short to discover the iPhone's _remotepairing-manual-pairing
service. This helper uses a longer (default 30 s) window and pairs **exactly
one** selected device — never all advertisements on the LAN.

Usage:
    sudo python3 scripts/pair_wifi.py [--timeout 30] [--name <exact-or-unique-substring>]

Selection rules (fail closed):
    - 0 devices found → exit 2
    - 1 device and no --name → pair that device
    - 2+ devices and no --name → exit 4 (ambiguous; require --name)
    - --name provided:
        * prefer exact Bonjour name match
        * else unique substring match on name
        * 0 matches → exit 5
        * 2+ matches → exit 4

PRE-REQUISITES on the iPhone:
    1. Developer Mode is ON (Settings → Privacy & Security → Developer Mode).
    2. The iPhone is on the SAME WiFi network as this Mac.
    3. The iPhone is UNLOCKED.
    4. Manual-pairing mode is ENABLED on iOS when required by the OS version.

The helper requires sudo because the underlying pmd3 pair flow needs root
to bind to the multicast group / write the pair record into a system path.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from typing import Any, Optional, Sequence, Tuple

# pmd3 9.x APIs
from pymobiledevice3.bonjour import (
    REMOTEPAIRING_MANUAL_PAIRING_SERVICE_NAME,
    browse_remotepairing_manual_pairing,
)
from pymobiledevice3.remote.tunnel_service import RemotePairingManualPairingService


def device_name(device: Any) -> str:
    return str(getattr(device, "name", "") or "")


def select_single_device(
    devices: Sequence[Any],
    name_filter: Optional[str],
) -> Tuple[Optional[Any], Optional[str]]:
    """
    Choose exactly one device to pair.

    Returns (device, None) on success, or (None, reason) where reason is one of:
    no_devices | ambiguous | no_match
    """
    devices = list(devices)
    if not devices:
        return None, "no_devices"

    filter_text = (name_filter or "").strip()
    if not filter_text:
        if len(devices) == 1:
            return devices[0], None
        return None, "ambiguous"

    exact = [d for d in devices if device_name(d) == filter_text]
    if len(exact) == 1:
        return exact[0], None
    if len(exact) > 1:
        return None, "ambiguous"

    substring = [d for d in devices if filter_text in device_name(d)]
    if len(substring) == 1:
        return substring[0], None
    if len(substring) == 0:
        return None, "no_match"
    return None, "ambiguous"


async def discover(timeout: float) -> list:
    print(
        f"[pair-wifi] Browsing for {REMOTEPAIRING_MANUAL_PAIRING_SERVICE_NAME} "
        f"for up to {timeout:.0f}s …",
        flush=True,
    )
    devices = await browse_remotepairing_manual_pairing(timeout=timeout)
    return devices


async def pair_one(svc_instance: Any) -> int:
    if not getattr(svc_instance, "ips", None):
        print(f"[pair-wifi] Device {device_name(svc_instance)} has no usable IPs", flush=True)
        return 1
    address = svc_instance.ips[0]
    port = svc_instance.port
    name = device_name(svc_instance)
    print(f"[pair-wifi] Connecting to {name} at {address}:{port}", flush=True)
    service = RemotePairingManualPairingService(hostname=address, port=port)
    print(
        "[pair-wifi] Initiating manual pair (you may need to confirm on the iPhone)",
        flush=True,
    )
    try:
        await service.connect(autopair=True)
    finally:
        await service.close()
    print("[pair-wifi] Pair record written.", flush=True)
    return 0


def _print_device_list(devices: Sequence[Any]) -> None:
    print(f"[pair-wifi] Found {len(devices)} device(s):")
    for d in devices:
        print(f"[pair-wifi]   - {device_name(d)}  ips={getattr(d, 'ips', None)}  port={getattr(d, 'port', None)}")


async def main_async(args: argparse.Namespace) -> int:
    devices = await discover(args.timeout)
    if not devices:
        print(
            "[pair-wifi] FAILED: no _remotepairing-manual-pairing instances "
            "found on the local network.\n"
            "[pair-wifi] On the iPhone:\n"
            "[pair-wifi]   1. Make sure it is on the SAME WiFi as this Mac.\n"
            "[pair-wifi]   2. Make sure it is UNLOCKED.\n"
            "[pair-wifi]   3. Open Settings → Developer (only visible with\n"
            "[pair-wifi]      Developer Mode ON) and ensure wireless pairing\n"
            "[pair-wifi]      is allowed.\n"
            "[pair-wifi]   4. Sometimes a brief Wi-Fi off→on toggle re-advertises.\n"
            f"[pair-wifi]   5. Re-run this script with a longer --timeout (e.g. 60).\n",
            file=sys.stderr,
        )
        return 2

    _print_device_list(devices)
    selected, reason = select_single_device(devices, args.name)
    if reason == "no_devices":
        return 2
    if reason == "no_match":
        print(
            f"[pair-wifi] FAILED: no device matched --name {args.name!r}. "
            "Use an exact Bonjour name or a unique substring.",
            file=sys.stderr,
        )
        return 5
    if reason == "ambiguous":
        print(
            "[pair-wifi] FAILED: multiple devices found; refusing to pair all of them (PC-F-001).\n"
            "[pair-wifi] Re-run with --name <exact-or-unique-Bonjour-name> to select one device.",
            file=sys.stderr,
        )
        return 4

    assert selected is not None
    print(f"[pair-wifi] Selected single device: {device_name(selected)}", flush=True)
    return await pair_one(selected)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pair this Mac with exactly one iPhone over WiFi (pmd3 9.x)"
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="Bonjour browse window in seconds (default 30)",
    )
    parser.add_argument(
        "--name",
        type=str,
        default=None,
        help=(
            "Select one device by exact Bonjour name, or a unique substring. "
            "Required when more than one device is advertising."
        ),
    )
    args = parser.parse_args()

    if os.geteuid() != 0:
        print(
            "[pair-wifi] WARNING: running without sudo — pmd3 may refuse to "
            "browse Bonjour. If you see 'requires root privileges', re-run with sudo.",
            file=sys.stderr,
        )

    try:
        rc = asyncio.run(main_async(args))
    except Exception as exc:
        print(f"[pair-wifi] EXCEPTION: {type(exc).__name__}: {exc}", file=sys.stderr)
        rc = 3
    sys.exit(rc)


if __name__ == "__main__":
    main()
