#!/usr/bin/env python3
"""
WiFi pairing helper for PathChanger.

`pymobiledevice3 remote pair` uses a 3-second Bonjour browse window which is
sometimes too short to discover the iPhone's _remotepairing-manual-pairing
service. This helper does the same pairing with a longer (default 30 s)
window, and prints clearer guidance about the iOS-side activation step.

Usage:
    sudo python3 scripts/pair_wifi.py [--timeout 30]

PRE-REQUISITES on the iPhone:
    1. Developer Mode is ON (Settings → Privacy & Security → Developer Mode).
    2. The iPhone is on the SAME WiFi network as this Mac.
    3. The iPhone is UNLOCKED.
    4. Manual-pairing mode is ENABLED on iOS. On iOS 17/18/26.x this is in:
         Settings → Developer → "Pair Wirelessly" / "Wireless Pairing"
       (the exact label varies by iOS version). Some iOS releases auto-advertise
       once Developer Mode is on and the device has been unlocked recently.

The helper requires sudo because the underlying pmd3 pair flow needs root
to bind to the multicast group / write the pair record into a system path.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

# pmd3 9.x APIs
from pymobiledevice3.bonjour import (
    REMOTEPAIRING_MANUAL_PAIRING_SERVICE_NAME,
    browse_remotepairing_manual_pairing,
)
from pymobiledevice3.remote.tunnel_service import RemotePairingManualPairingService


async def discover(timeout: float) -> list:
    print(f"[pair-wifi] Browsing for {REMOTEPAIRING_MANUAL_PAIRING_SERVICE_NAME} "
          f"for up to {timeout:.0f}s …", flush=True)
    devices = await browse_remotepairing_manual_pairing(timeout=timeout)
    return devices


async def pair_one(svc_instance, name_filter: str | None) -> int:
    # Pull addresses + port out of the ServiceInstance
    if not getattr(svc_instance, "ips", None):
        print(f"[pair-wifi] Device {svc_instance.name} has no usable IPs", flush=True)
        return 1
    address = svc_instance.ips[0]
    port = svc_instance.port
    name = svc_instance.name
    if name_filter and name_filter not in name:
        print(f"[pair-wifi] Skipping {name} (does not match --name {name_filter})", flush=True)
        return 0
    print(f"[pair-wifi] Connecting to {name} at {address}:{port}", flush=True)
    service = RemotePairingManualPairingService(hostname=address, port=port)
    print("[pair-wifi] Initiating manual pair (you may need to confirm on the iPhone)", flush=True)
    try:
        await service.connect(autopair=True)
    finally:
        await service.close()
    print("[pair-wifi] Pair record written.", flush=True)
    return 0


async def main_async(args) -> int:
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
    print(f"[pair-wifi] Found {len(devices)} device(s):")
    for d in devices:
        print(f"[pair-wifi]   - {d.name}  ips={d.ips}  port={d.port}")
    rc = 0
    for d in devices:
        rc = await pair_one(d, args.name)
        if rc != 0:
            return rc
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Pair this Mac with an iPhone over WiFi (pmd3 9.x)")
    parser.add_argument("--timeout", type=float, default=30.0,
                        help="Bonjour browse window in seconds (default 30)")
    parser.add_argument("--name", type=str, default=None,
                        help="Only pair with the device whose Bonjour name contains this substring")
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("[pair-wifi] WARNING: running without sudo — pmd3 may refuse to "
              "browse Bonjour. If you see 'requires root privileges', re-run with sudo.",
              file=sys.stderr)

    try:
        rc = asyncio.run(main_async(args))
    except Exception as exc:
        print(f"[pair-wifi] EXCEPTION: {type(exc).__name__}: {exc}", file=sys.stderr)
        rc = 3
    sys.exit(rc)


if __name__ == "__main__":
    main()
