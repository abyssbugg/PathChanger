#!/usr/bin/env python3
"""Prove the helper's service-construction path applies location.

Run with the managed runtime python while the phone is unlocked —
owner-supervised only:

    ~/Library/Application\\ Support/PathChanger/runtime/location/bin/python3 \\
        scripts/verify_bridge_lane.py --udid <UDID> --lat 37.785834 --lng -122.406417

The script dials the device through DeviceConnection._get_or_create_service —
the exact construction path the persistent bridge server serves requests
with (no parallel construction logic) — then sets one coordinate and holds
so the spoof can be observed on the device map.

Success = the APPLIED line printed with the channel that served it, and map
movement observed on the phone. Do not run against a device without owner
authorization: physical-device work requires an approved plan (CLAUDE.md §10).
"""

import argparse
import asyncio
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from location_bridge import DeviceConnection  # noqa: E402  (same-directory import)


async def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify the location bridge's service-construction lanes end to end."
    )
    parser.add_argument("--udid", required=True, help="Target device UDID")
    parser.add_argument("--lat", type=float, required=True)
    parser.add_argument("--lng", type=float, required=True)
    parser.add_argument("--rsd-address", default=None, help="Explicit RSD endpoint address (fallback lane)")
    parser.add_argument("--rsd-port", type=int, default=None, help="Explicit RSD endpoint port (fallback lane)")
    parser.add_argument("--connection-type", choices=["USB", "Network"], default=None)
    parser.add_argument("--hold", type=float, default=30.0, help="Seconds to hold the applied coordinate")
    args = parser.parse_args()

    if not (-90 <= args.lat <= 90) or not (-180 <= args.lng <= 180):
        print("ERROR: lat must be within [-90, 90] and lng within [-180, 180]", file=sys.stderr)
        return 1
    if (args.rsd_address is None) != (args.rsd_port is None):
        print("ERROR: --rsd-address and --rsd-port must be supplied together", file=sys.stderr)
        return 1

    connection = DeviceConnection()
    if not connection._lazy_import():
        print("ERROR: pymobiledevice3 is not importable from this interpreter", file=sys.stderr)
        return 1

    try:
        _, location, channel, endpoint_class = await connection._get_or_create_service(
            udid=args.udid,
            rsd_address=args.rsd_address,
            rsd_port=args.rsd_port,
            connection_type=args.connection_type,
        )
    except Exception as error:
        print(f"CONSTRUCTION FAILED: {error}", file=sys.stderr)
        return 1
    print(f"CHANNEL={channel} ENDPOINT_CLASS={endpoint_class}", flush=True)

    try:
        await location.set(args.lat, args.lng)
    except Exception as error:
        print(f"SET FAILED: {error}", file=sys.stderr)
        return 1
    print(f"APPLIED lat={args.lat} lng={args.lng} channel={channel}", flush=True)

    # Held-session semantics: the spoof lives only while this process stays running.
    # Hold and report progress so the observed window is explicit.
    deadline = time.monotonic() + args.hold
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            print(f"HOLDING {remaining:.0f}s — observe the device map", flush=True)
            await asyncio.sleep(min(5.0, remaining))
    finally:
        try:
            await asyncio.shield(connection.close_all())
        except Exception:
            pass
    print(f"HELD DONE lat={args.lat} lng={args.lng} channel={channel}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
