#!/usr/bin/env python3
"""
Persistent Location Bridge for PathChanger (pymobiledevice3 9.x API)

Maintains a persistent asyncio event loop and a cached DVT/LocationSimulation
session per device, so high-frequency callers (Multi-Spot route playback,
Joystick) get ~10-20 ms per location update instead of ~5-15 s per fresh
subprocess.

Protocol (JSON over stdin/stdout, one object per line):
    Request:  {"request_id": "<uuid>", "cmd": "set_location", "lat": 37.78, "lng": -122.40,
               "udid": "<UDID>",
               "rsd_address": "fd8a:8bb8::1", "rsd_port": 12345}
    Response: {"request_id": "<uuid>", "success": true}
              or {"request_id": "<uuid>", "success": false, "error": "..."}

Commands: set_location, clear_location, ping, quit

The pmd3 9.x DVT API moved to async context managers:
    async with RemoteServiceDiscoveryService((addr, port)) as rsd, \\
               DvtProvider(rsd) as dvt, \\
               LocationSimulation(dvt) as ls:
        await ls.set(lat, lng)

This bridge keeps those async context managers OPEN across calls by manually
driving __aenter__ / __aexit__ on a long-lived asyncio loop.
"""

import asyncio
import json
import signal
import sys
import threading
from typing import Any, Optional, Tuple

# --- Lazy imports ---------------------------------------------------------
#
# pmd3 import paths changed between 8.x and 9.x. We import lazily so the
# bridge can still send useful error responses if pmd3 isn't installed.
_IMPORT_ERROR: Optional[str] = None
DvtProvider = None  # type: ignore
LocationSimulation = None  # type: ignore
RemoteServiceDiscoveryService = None  # type: ignore
create_using_usbmux = None  # type: ignore


def _lazy_import() -> bool:
    """Import pmd3 9.x symbols. Returns True on success."""
    global _IMPORT_ERROR, DvtProvider, LocationSimulation
    global RemoteServiceDiscoveryService, create_using_usbmux
    if DvtProvider is not None:
        return True
    try:
        from pymobiledevice3.services.dvt.instruments.dvt_provider import (
            DvtProvider as _DvtProvider,
        )
        from pymobiledevice3.services.dvt.instruments.location_simulation import (
            LocationSimulation as _LocationSimulation,
        )
        from pymobiledevice3.remote.remote_service_discovery import (
            RemoteServiceDiscoveryService as _RSD,
        )
        from pymobiledevice3.lockdown import (
            create_using_usbmux as _create_using_usbmux,
        )
        DvtProvider = _DvtProvider
        LocationSimulation = _LocationSimulation
        RemoteServiceDiscoveryService = _RSD
        create_using_usbmux = _create_using_usbmux
        return True
    except Exception as exc:
        _IMPORT_ERROR = f"{type(exc).__name__}: {exc}"
        return False


# --- Async session cache --------------------------------------------------

class _CachedSession:
    """Wraps the three async context managers we need for one device.

    We hold the entered values so we can call .set()/.clear() repeatedly
    without re-doing the (slow) DVT handshake. On error or shutdown we
    invoke __aexit__ in reverse order to release resources cleanly.
    """

    def __init__(self) -> None:
        self.rsd: Any = None
        self.dvt_cm: Any = None
        self.dvt: Any = None
        self.ls_cm: Any = None
        self.ls: Any = None

    async def open(
        self,
        udid: str,
        rsd_address: Optional[str],
        rsd_port: Optional[int],
    ) -> None:
        if rsd_address and rsd_port:
            self.rsd = RemoteServiceDiscoveryService((rsd_address, int(rsd_port)))
            await self.rsd.connect()
            service_provider = self.rsd
        else:
            # USB-only fallback path; on iOS 17+ this normally fails because
            # DVT requires the lockdown tunnel, but we keep it for older OSes.
            service_provider = create_using_usbmux(serial=udid)

        self.dvt_cm = DvtProvider(service_provider)
        self.dvt = await self.dvt_cm.__aenter__()
        self.ls_cm = LocationSimulation(self.dvt)
        self.ls = await self.ls_cm.__aenter__()

    async def close(self) -> None:
        # Reverse order of opens; swallow errors so one bad close doesn't
        # stop the others.
        for cm in (self.ls_cm, self.dvt_cm):
            if cm is not None:
                try:
                    await cm.__aexit__(None, None, None)
                except Exception:
                    pass
        if self.rsd is not None:
            try:
                await self.rsd.close()
            except Exception:
                pass
        self.rsd = self.dvt_cm = self.dvt = self.ls_cm = self.ls = None


class AsyncBridge:
    """Keeps one cached _CachedSession per (udid, rsd_address, rsd_port)."""

    def __init__(self) -> None:
        self._cache: dict[Tuple[str, Optional[str], Optional[int]], _CachedSession] = {}

    async def _get(
        self,
        udid: str,
        rsd_address: Optional[str],
        rsd_port: Optional[int],
    ) -> _CachedSession:
        key = (udid, rsd_address, rsd_port)
        sess = self._cache.get(key)
        if sess is not None:
            return sess
        sess = _CachedSession()
        try:
            await sess.open(udid, rsd_address, rsd_port)
        except Exception:
            # Don't pollute the cache with a half-open session.
            await sess.close()
            raise
        self._cache[key] = sess
        return sess

    async def _drop(
        self,
        udid: str,
        rsd_address: Optional[str],
        rsd_port: Optional[int],
    ) -> None:
        key = (udid, rsd_address, rsd_port)
        sess = self._cache.pop(key, None)
        if sess is not None:
            await sess.close()

    async def set_location(
        self,
        lat: float,
        lng: float,
        udid: str,
        rsd_address: Optional[str],
        rsd_port: Optional[int],
    ) -> dict:
        try:
            sess = await self._get(udid, rsd_address, rsd_port)
            await sess.ls.set(lat, lng)
            return {"success": True}
        except Exception as exc:
            # On error, drop the cached session so the next call reconnects.
            await self._drop(udid, rsd_address, rsd_port)
            return {"success": False, "error": f"{type(exc).__name__}: {exc}"}

    async def clear_location(
        self,
        udid: str,
        rsd_address: Optional[str],
        rsd_port: Optional[int],
    ) -> dict:
        try:
            sess = await self._get(udid, rsd_address, rsd_port)
            await sess.ls.clear()
            return {"success": True}
        except Exception as exc:
            await self._drop(udid, rsd_address, rsd_port)
            return {"success": False, "error": f"{type(exc).__name__}: {exc}"}

    async def close_all(self) -> None:
        for sess in list(self._cache.values()):
            try:
                await sess.close()
            except Exception:
                pass
        self._cache.clear()


# --- Validation ----------------------------------------------------------

def _validate_request(request: Any) -> Tuple[bool, str]:
    if not isinstance(request, dict):
        return False, "Request must be a JSON object"
    request_id = request.get("request_id")
    if not isinstance(request_id, str) or not request_id:
        return False, "Missing or invalid 'request_id' field"
    cmd = request.get("cmd")
    if cmd not in ("set_location", "clear_location", "ping", "quit"):
        return False, f"Unknown command: {cmd!r}"
    if cmd in ("set_location", "clear_location"):
        udid = request.get("udid")
        if not isinstance(udid, str) or not udid:
            return False, "Missing or invalid 'udid' field"
    if cmd == "set_location":
        try:
            lat = float(request.get("lat"))
            lng = float(request.get("lng"))
        except (TypeError, ValueError):
            return False, "Invalid coordinates"
        if not (-90.0 <= lat <= 90.0):
            return False, "Latitude out of range"
        if not (-180.0 <= lng <= 180.0):
            return False, "Longitude out of range"
    return True, ""


# --- Main loop -----------------------------------------------------------

_shutdown_requested = False


def _signal_handler(signum, frame):  # noqa: ARG001
    global _shutdown_requested
    _shutdown_requested = True


signal.signal(signal.SIGTERM, _signal_handler)
signal.signal(signal.SIGINT, _signal_handler)


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _response_for(request: dict, payload: dict) -> dict:
    response = dict(payload)
    request_id = request.get("request_id")
    if isinstance(request_id, str):
        response["request_id"] = request_id
    return response


async def _serve(bridge: AsyncBridge) -> None:
    """Read NDJSON requests from stdin and write NDJSON responses to stdout."""
    _emit({"ready": True})

    loop = asyncio.get_running_loop()
    try:
        while not _shutdown_requested:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                break  # EOF
            line = line.strip()
            if not line:
                continue

            try:
                request = json.loads(line)
            except json.JSONDecodeError as exc:
                _emit({"success": False, "error": f"Invalid JSON: {exc}"})
                continue

            valid, msg = _validate_request(request)
            if not valid:
                if isinstance(request, dict):
                    _emit(_response_for(request, {"success": False, "error": msg}))
                else:
                    _emit({"success": False, "error": msg})
                continue

            cmd = request["cmd"]

            if cmd == "ping":
                _emit(_response_for(request, {"success": True, "message": "pong"}))
                continue

            if cmd == "quit":
                _emit(_response_for(request, {"success": True, "message": "shutting down"}))
                break

            if not _lazy_import():
                _emit(_response_for(request, {
                    "success": False,
                    "error": f"pymobiledevice3 import failed: {_IMPORT_ERROR}",
                }))
                continue

            if cmd == "set_location":
                result = await bridge.set_location(
                    lat=float(request["lat"]),
                    lng=float(request["lng"]),
                    udid=request["udid"],
                    rsd_address=request.get("rsd_address"),
                    rsd_port=request.get("rsd_port"),
                )
                _emit(_response_for(request, result))
                continue

            if cmd == "clear_location":
                result = await bridge.clear_location(
                    udid=request["udid"],
                    rsd_address=request.get("rsd_address"),
                    rsd_port=request.get("rsd_port"),
                )
                _emit(_response_for(request, result))
                continue

            # Defense-in-depth: should be unreachable due to validation
            _emit(_response_for(request, {"success": False, "error": f"Unhandled command: {cmd}"}))
    finally:
        await bridge.close_all()


def _emit_fatal(exc: BaseException) -> None:
    message = f"Fatal bridge error: {type(exc).__name__}: {exc}"
    try:
        _emit({"fatal": True, "success": False, "error": message})
    except Exception:
        pass
    print(message, file=sys.stderr, flush=True)


def main() -> None:
    bridge = AsyncBridge()
    try:
        asyncio.run(_serve(bridge))
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        _emit_fatal(exc)
        raise


if __name__ == "__main__":
    main()
