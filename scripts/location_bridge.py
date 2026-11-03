#!/usr/bin/env python3
"""
Persistent Location Bridge for PathChanger

This script maintains a persistent connection to iOS devices for efficient
location injection. It reads JSON commands from stdin and writes JSON
responses to stdout.

Protocol:
    Request:  {"cmd": "set_location", "lat": 37.785834, "lng": -122.406417, "udid": "DEVICE_UDID", "rsd_address": null, "rsd_port": null}
    Response: {"success": true} or {"success": false, "error": "message"}

Commands:
    - connect_device: Open (or reuse) the device connection and prove DVT answers
    - connection_status: Bounded liveness probe of the device connection
    - disconnect_device: Close the device connection (ends a held location)
    - ddi_status / ddi_mount: Developer Disk Image status / auto-mount over the held
      device connection (never opens one)
    - set_location / clear_location: Simulate or stop simulating a location
    - ping: Helper health check (touches no device)
    - quit: Graceful shutdown

Device connection (owner decision 2026-11-01, "Option A"): this helper owns the
ONLY connection to each device, one in-process pymobiledevice3 userspace tunnel.
The app's `remote start-tunnel --native` RSD refused the location service 3/3 on
iOS 27.2 while this tunnel served it 3/3, so RSD endpoints supplied by the app
are ignored.

Security:
    - Input validation on all JSON fields
    - No arbitrary command execution
    - Rate limiting handled by Swift layer
"""

import argparse
import asyncio
import hashlib
import hmac
import ipaddress
import json
import os
import signal
import stat
import sys
import traceback
import time
import uuid
from typing import Optional, Tuple
from contextlib import AsyncExitStack

# Every device call is bounded: a silently dropped Wi-Fi link produces no EOF, and
# an unbounded await would park the request (and the app's request gate) forever.
CONNECT_TIMEOUT_SECONDS = 30.0
DEVICE_OPERATION_TIMEOUT_SECONDS = 10.0
# A healthy DVT listing answers in ~40 ms; 3 s bounds the loss-detection window.
PROBE_TIMEOUT_SECONDS = 3.0

# The Developer Disk Image commands run over the held device connection. A status check
# is one image-mounter round trip; an auto-mount may download and personalize the image
# (live 2026-10-31: ~30 s including the cryptex download), so it gets a longer bound.
DDI_STATUS_TIMEOUT_SECONDS = DEVICE_OPERATION_TIMEOUT_SECONDS
DDI_MOUNT_TIMEOUT_SECONDS = 120.0

# How long the mobdev2 lane browses Bonjour for the phone's lockdown (live
# 2026-11-01: found in 1.7 s). The whole open stays inside CONNECT_TIMEOUT_SECONDS.
MOBDEV2_BROWSE_TIMEOUT_SECONDS = 8.0

# How long the remote pairing lane browses RemotePairing Bonjour for the phone (live
# 2026-11-02, read-only: found and pair-verified in ~2 s at a rotated address).
REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS = 8.0

# The bound on the remote pairing lane's whole browse + connect + pair-verify. Upstream
# bounds the browse and each TCP open (1 s) but not the pair-verify handshake, so a phone
# that accepts TCP and then stalls would otherwise use the whole CONNECT_TIMEOUT_SECONDS
# open and mobdev2 would never run in that attempt (review 2026-11-03 issue 4). Above
# the browse bound, and leaves the mobdev2 lane its 8 s browse inside the 30 s open.
REMOTE_PAIRING_LANE_TIMEOUT_SECONDS = 12.0

# The mobdev2 lane points pymobiledevice3.remote.userspace_tunnel's module-global
# create_using_usbmux at its Bonjour lockdown for one tunnel open, and the remote
# pairing lane points its module-global _create_no_root_tunnel_provider at its
# RemotePairing service. Every userspace tunnel open in this process holds this lock,
# so no other open ever sees either swap.
_USBMUX_PROVIDER_SWAP_LOCK = asyncio.Lock()


class Mobdev2DeviceNotFoundError(LookupError):
    """mobdev2 Bonjour found no paired lockdown for the UDID."""


class Mobdev2BrowseError(OSError):
    """The mobdev2 Bonjour browse itself failed (mDNS socket); it observed no phone."""


class RemotePairingDeviceNotFoundError(LookupError):
    """RemotePairing Bonjour found no advert that accepted this Mac's pairing for the
    phone: no matching advert, or upstream skipped every address of a matching one
    because pair-verify failed, timed out or the socket errored."""


class RemotePairingBrowseError(OSError):
    """The RemotePairing Bonjour browse itself failed (mDNS socket); it observed no phone."""


class RemotePairingTimeoutError(TimeoutError):
    """The remote pairing lane's browse + connect did not finish within
    REMOTE_PAIRING_LANE_TIMEOUT_SECONDS. That bound exceeds the browse's own, so the
    stall came after an advert matched (a phone that accepts TCP and then stalls
    pair-verify): a Wi-Fi transport timeout, so Start keeps waiting."""


class RemotePairingRecordStaleError(LookupError):
    """This Mac has no RemotePairing record for the phone, or one without its altIRK, so
    RemotePairing Bonjour cannot recognize the phone. The lane looked at nothing."""


class LaneUnsupportedError(RuntimeError):
    """The installed pymobiledevice3 lacks an API this lane needs; the lane observed nothing."""


class LanesTimedOutError(TimeoutError):
    """No lane opened within CONNECT_TIMEOUT_SECONDS; names the lane that was in flight."""


# pymobiledevice3 raises these when usbmux does not list the device right now. An
# idle Wi-Fi phone drops out of usbmux for seconds to minutes (live 2026-11-01), so
# when every lane says this, the phone is not visible yet - not broken.
_DEVICE_ABSENT_ERRORS = frozenset({
    "DeviceNotFoundError", "NoDeviceConnectedError", Mobdev2DeviceNotFoundError.__name__,
    RemotePairingDeviceNotFoundError.__name__,
})

_MOBDEV2_LANE = "mobdev2"
_REMOTE_PAIRING_LANE = "remote pairing"
# The lanes that reach the phone over Wi-Fi (Bonjour), used when usbmux sees nothing.
_WIFI_LANES = frozenset({_MOBDEV2_LANE, _REMOTE_PAIRING_LANE})

# Lane failures that looked at nothing (a missing API, or a pair record that cannot
# match the phone): they neither prove nor disprove that the phone is visible.
_LANE_DID_NOT_LOOK = (LaneUnsupportedError, RemotePairingRecordStaleError)

# pymobiledevice3's own transport failures, matched by class name over the MRO (the
# helper does not import upstream exception classes at module load). Upstream wraps
# TLS-handshake and socket I/O failures (OSError, asyncio.TimeoutError) in
# ConnectionTerminatedError and dial failures in ConnectionFailedError; neither is a
# builtin ConnectionError (pymobiledevice3 11.49.1 service_connection.py).
_UPSTREAM_TRANSPORT_ERRORS = frozenset({"ConnectionTerminatedError", "ConnectionFailedError"})

# Errors only the real usbmux raises. Seen from the mobdev2 open before the swapped
# provider was asked, they show upstream dialed usbmux instead of reading the swap.
_USBMUX_LOOKUP_ERRORS = frozenset({"DeviceNotFoundError", "NoDeviceConnectedError", "MuxException"})

# Base class of every pymobiledevice3 exception.
_UPSTREAM_BASE_ERROR = "PyMobileDevice3Exception"


def _class_names(error: BaseException) -> set:
    return {cls.__name__ for cls in type(error).__mro__}


def _is_device_absent(error: BaseException) -> bool:
    return type(error).__name__ in _DEVICE_ABSENT_ERRORS


def _keeps_waiting(lane: str, error: BaseException, earlier=()) -> bool:
    """True when this lane failure leaves the phone possibly about to come back.

    Owner decision 2026-11-01: Start keeps trying while the phone may return. Only
    the Wi-Fi lanes (remote pairing and mobdev2, used when usbmux sees nothing) treat
    transport errors as "not visible yet": a reset, refused or timed-out Wi-Fi link to
    a dozing phone (builtin or pymobiledevice3's own transport classes), or a failed
    Bonjour browse. Running out of the whole open's time budget counts only while a
    Wi-Fi lane was in flight, or when every lane that finished before (`earlier`,
    at least one) said the phone is absent: a hang in lane 1 with nothing collected
    cannot be won by waiting for the phone. Any other failure is real.
    """
    if _is_device_absent(error):
        return True
    if isinstance(error, LanesTimedOutError):
        return lane in _WIFI_LANES or (
            bool(earlier) and all(_is_device_absent(previous) for _, previous in earlier)
        )
    if lane not in _WIFI_LANES:
        return False
    return isinstance(
        error,
        (ConnectionError, asyncio.TimeoutError, TimeoutError, Mobdev2BrowseError, RemotePairingBrowseError),
    ) or bool(_class_names(error) & _UPSTREAM_TRANSPORT_ERRORS)


class DeviceLanesUnavailable(RuntimeError):
    """Every connection lane failed; carries each lane's own error, in order."""

    def __init__(self, failures):
        self.failures = list(failures)
        # A lane that could not run (missing API) or could not match the phone (no
        # usable pair record) saw nothing either way, so it neither proves nor
        # disproves that the phone is visible.
        observed = [
            (lane, error) for lane, error in self.failures
            if not isinstance(error, _LANE_DID_NOT_LOOK)
        ]
        self.device_not_visible = bool(observed) and all(
            _keeps_waiting(lane, error, observed[:index])
            for index, (lane, error) in enumerate(observed)
        )
        details = "; ".join(
            f"{lane}: {type(error).__name__}: {error}" for lane, error in self.failures
        )
        super().__init__(f"DVT lanes unavailable ({details})")

# Graceful shutdown state
_shutdown_requested = False
_shutdown_event: Optional[asyncio.Event] = None
_event_loop: Optional[asyncio.AbstractEventLoop] = None


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully and wake a pending stdin read."""
    global _shutdown_requested
    _shutdown_requested = True
    if _event_loop is not None and _shutdown_event is not None and not _event_loop.is_closed():
        _event_loop.call_soon_threadsafe(_shutdown_event.set)


# Register signal handlers
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


async def _close_quietly(resource) -> None:
    """Close a lockdown-like resource; a close that fails leaves nothing to undo."""
    try:
        await resource.close()
    except Exception:
        pass


def _prefetch_ddi_assets(provider) -> None:
    """Fetch (or find cached) the image `auto_mount` would use for this device.

    Runs in a worker thread: pymobiledevice3 downloads the Cryptex1 bundle / the
    PersonalizedDMG synchronously inside its async auto_mount, which would stop this
    helper's event loop (every other client, the liveness probe included) for the whole
    download. Both fetches cache under the pymobiledevice3 home folder, so auto_mount
    then reads the cache. The choice mirrors auto_mount_personalized. Below iOS 17 (a
    classic image) nothing is fetched here. If the installed pymobiledevice3 moved these
    helpers, nothing is fetched and auto_mount behaves as before.
    """
    try:
        from pymobiledevice3.services import mobile_image_mounter as mounter
        from pymobiledevice3.services.cryptexd import fetch_cryptex_ddi
        from packaging.version import Version
        uses_personalized = mounter.uses_personalized_image
        uses_cryptex = mounter.uses_cryptex_image
        fetch_personalized = mounter.fetch_personalized_ddi
        cryptex_minimum = mounter.CRYPTEX_IMAGE_MIN_VERSION
        rsd_type = mounter.RemoteServiceDiscoveryService
    except (ImportError, AttributeError):
        return
    if not uses_personalized(provider):
        return
    if uses_cryptex(provider):
        fetch_cryptex_ddi()
    elif isinstance(provider, rsd_type) or Version(provider.product_version) < cryptex_minimum:
        # Otherwise auto_mount refuses plain lockdown on iOS 27+ before fetching anything.
        fetch_personalized()


class DeviceConnection:
    """Manages cached connection to a device's DVT service."""
    
    def __init__(self):
        self._service_cache: dict = {}
        self._dvt_module = None
        self._lockdown_module = None
        self._tunnel_module = None
        self._preferred_tunnel_factory = None
        self._tunnel_required_errors: tuple = ()
        self._device_info_module = None
        self._mobdev2_lockdowns = None
        self._remote_pairing_services = None
        self._remote_pair_records = None
        self._peer_alt_irk_key = None
        self._userspace_tunnel_module = None
        self._image_mounter_service = None
        self._ddi_auto_mount = None
        self._ddi_prefetch = None
        self._already_mounted_error = None
        self._ddi_mount_locks: dict = {}
        # Per device: mounts that succeeded (a mount queued behind one returns mounted), and
        # the image download in flight (one at a time, also across a timed-out mount).
        self._ddi_mount_successes: dict = {}
        self._ddi_prefetch_tasks: dict = {}
        self._open_locks: dict = {}
        # Called with the device id whenever its connection is closed, so the helper
        # record never lists a held location on a connection that no longer exists.
        self.on_connection_closed = None
        self._initialized = False
    
    def _lazy_import(self):
        """Import pymobiledevice3 modules lazily to avoid import errors on startup."""
        if self._initialized:
            return True
            
        try:
            from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
            from pymobiledevice3.services.dvt.instruments.device_info import DeviceInfo
            from pymobiledevice3.lockdown import create_using_usbmux, create_using_tcp
            from pymobiledevice3.remote.rsd_tunnel import PreferredRsdTunnel
            from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
            import pymobiledevice3.remote.userspace_tunnel as userspace_tunnel_module
            from pymobiledevice3.exceptions import InvalidServiceError, RSDRequiredError
            # Optional (rolling-latest: the API may move): without it only the
            # mobdev2 lane is unavailable, and it says so.
            try:
                from pymobiledevice3.lockdown import get_mobdev2_lockdowns
            except ImportError:
                get_mobdev2_lockdowns = None
            # Optional too: without them only the remote pairing lane is unavailable.
            try:
                from pymobiledevice3.remote.tunnel_service import (
                    PEER_ALT_IRK_KEY, get_remote_pairing_tunnel_services,
                )
                from pymobiledevice3.pair_records import iter_remote_pair_records_by_identifier
            except ImportError:
                PEER_ALT_IRK_KEY = None
                get_remote_pairing_tunnel_services = None
                iter_remote_pair_records_by_identifier = None
            # Optional too: without them only the DDI commands are unavailable.
            try:
                from pymobiledevice3.services.mobile_image_mounter import (
                    MobileImageMounterService, auto_mount,
                )
                from pymobiledevice3.exceptions import AlreadyMountedError
            except ImportError:
                MobileImageMounterService = None
                auto_mount = None
                AlreadyMountedError = None

            self._image_mounter_service = MobileImageMounterService
            self._ddi_auto_mount = auto_mount
            self._ddi_prefetch = _prefetch_ddi_assets
            self._already_mounted_error = AlreadyMountedError
            self._mobdev2_lockdowns = get_mobdev2_lockdowns
            self._remote_pairing_services = get_remote_pairing_tunnel_services
            self._remote_pair_records = iter_remote_pair_records_by_identifier
            self._peer_alt_irk_key = PEER_ALT_IRK_KEY
            self._userspace_tunnel_module = userspace_tunnel_module
            self._dvt_module = DvtProvider
            self._location_module = LocationSimulation
            self._device_info_module = DeviceInfo
            self._lockdown_usb = create_using_usbmux
            self._lockdown_tcp = create_using_tcp
            self._preferred_tunnel_factory = PreferredRsdTunnel
            self._userspace_tunnel_factory = UserspaceRsdTunnel
            self._tunnel_required_errors = (InvalidServiceError, RSDRequiredError)
            self._initialized = True
            return True
        except ImportError as e:
            return False
    
    @staticmethod
    def _cache_key(udid: str, connection_type: Optional[str]) -> str:
        # One connection per device, whatever transport hint the caller sends:
        # pymobiledevice3 allows a single userspace tunnel per process, and the
        # GUI's Start Tunnel and Move must share it.
        return udid

    def _open_lock(self, cache_key: str) -> asyncio.Lock:
        lock = self._open_locks.get(cache_key)
        if lock is None:
            lock = asyncio.Lock()
            self._open_locks[cache_key] = lock
        return lock

    async def _get_or_create_service(
        self,
        udid: str,
        connection_type: Optional[str] = None,
    ) -> Tuple[any, any, str, str]:
        """Return the device's single connection, opening it on first use.

        HELPER-OWNED CONNECTION (owner decision 2026-11-01, Option A): this helper
        is the only owner of the device connection. RSD endpoints supplied by the
        app are not dialed: the app's `--native` tunnel refused the location
        service 3/3 on iOS 27.2 while this helper's own tunnel served it 3/3.

        Opening is serialized per device: pymobiledevice3 allows one userspace
        tunnel per process, so a concurrent connect and set must share one open.
        A new connection is reported only after DVT answers a directory listing.

        Dial order follows the LIVE-PROVEN CLI behavior (owner-observed 2026-10-31):

        1. no-root userspace tunnel FIRST — ``UserspaceRsdTunnel`` with
           ``remotepairing_fallback=False``, the exact construction the CLI makes
           after its InvalidServiceError re-exec. The previous usbmux-first order
           silently broke device-side application: the tunnel lane connected and
           ``set()`` succeeded, but the device never applied the location unless
           nothing usbmux/lockdown had been attempted in the process before it.
        2. usbmux-direct lockdown (``create_using_usbmux``) — devices whose
           developer commands are served over lockdown directly.
        3. the full ``PreferredRsdTunnel`` chain (native remoted included) last —
           covers iOS 17.0-17.3 (no CoreDeviceProxy) and exotic deployments.
        4. remote pairing — only after every usbmux-backed lane failed (live
           2026-11-02: once the phone's private Wi-Fi address rotated, usbmuxd listed
           nothing for hours): RemotePairing Bonjour finds the phone at any address by
           the altIRK in its RemotePairing record, then the same userspace tunnel opens
           over that RemotePairing service. Proven live read-only, no usbmuxd.
        5. mobdev2 — after that: the same userspace tunnel over a mobdev2 TCP lockdown
           (live 2026-11-01: usbmux listed no Wi-Fi phone for 3.5 minutes while Bonjour
           still reached its lockdown).
           Lanes 4 and 5 reach the phone over Wi-Fi: skipped when the request names USB.
        """
        if connection_type not in (None, "USB", "Network"):
            raise ValueError("connection_type must be USB or Network")
        cache_key = self._cache_key(udid, connection_type)
        async with self._open_lock(cache_key):
            cached = self._service_cache.get(cache_key)
            if cached is None:
                failures, progress = [], {}
                try:
                    await asyncio.wait_for(
                        self._open_lanes(udid, cache_key, connection_type, failures, progress),
                        CONNECT_TIMEOUT_SECONDS,
                    )
                except asyncio.TimeoutError as timeout:
                    # No lane opened in time. Keep what each finished lane said, and
                    # name the one still in flight, so the verdict and the text are
                    # the same as if that lane had failed on its own.
                    in_flight = progress.get("lane", "lanes")
                    failures.append((in_flight, LanesTimedOutError(
                        f"no lane opened within {CONNECT_TIMEOUT_SECONDS:g}s")))
                    raise DeviceLanesUnavailable(failures) from timeout
                opened = self._service_cache.get(cache_key)
                try:
                    await self._prove_dvt(cache_key)
                except BaseException:
                    await self._invalidate(cache_key, opened)
                    raise
                cached = self._service_cache.get(cache_key)
                if cached is None or cached is not opened:
                    raise RuntimeError("device connection closed while opening")
            return (
                cached["dvt"], cached["location"],
                cached["channel"], cached["endpoint_class"],
            )

    async def _open_lanes(
        self, udid: str, cache_key: str, connection_type: Optional[str],
        failures: Optional[list] = None, progress: Optional[dict] = None,
    ) -> None:
        # Each lane's own error is kept: reporting only the last lane's hid why the
        # primary lane failed (the GUI always showed the usbmux lane's message).
        # `failures` and `progress` belong to the caller, so a timeout around this
        # call still knows what every lane said and which one was in flight.
        failures = [] if failures is None else failures
        progress = {} if progress is None else progress
        lanes = [
            ("userspace tunnel", lambda: self._open_userspace_tunnel_cli_exact(udid, cache_key)),
            ("usbmux direct", lambda: self._open_usbmux_direct(udid, cache_key, connection_type)),
            ("preferred RSD", lambda: self._open_preferred_rsd(udid, cache_key)),
        ]
        # The remote pairing and mobdev2 lanes reach the phone over Wi-Fi (Bonjour): a
        # request that names USB never crosses to Wi-Fi.
        if connection_type in (None, "Network"):
            lanes.append((_REMOTE_PAIRING_LANE, lambda: self._open_remote_pairing(udid, cache_key)))
            lanes.append((_MOBDEV2_LANE, lambda: self._open_mobdev2(udid, cache_key)))
        for lane, open_lane in lanes:
            progress["lane"] = lane
            try:
                await open_lane()
                return
            except Exception as error:
                failures.append((lane, error))
        raise DeviceLanesUnavailable(failures) from failures[-1][1]

    async def _prove_dvt(self, cache_key: str, cached: Optional[dict] = None) -> None:
        """Prove the DVT service answers: list `/` over the connection itself."""
        if cached is None:
            cached = self._service_cache[cache_key]
        if self._device_info_module is None:
            return
        info = cached.get("device_info")
        if info is None:
            info = await asyncio.wait_for(
                cached["stack"].enter_async_context(self._device_info_module(cached["dvt"])),
                PROBE_TIMEOUT_SECONDS,
            )
            cached["device_info"] = info
        await asyncio.wait_for(info.ls("/"), PROBE_TIMEOUT_SECONDS)

    async def connect_device(self, udid: str, connection_type: Optional[str] = None) -> dict:
        """Open (or reuse) the device connection; the GUI's Start Tunnel."""
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}
        cache_key = self._cache_key(udid, connection_type)
        # An explicit connect must not report a stalled connection as live (probe
        # timeouts keep connections open): prove it, or replace it and say so -
        # replacing a connection ends any location held over it.
        replaced = False
        async with self._open_lock(cache_key):
            cached = self._service_cache.get(cache_key)
            if cached is not None:
                try:
                    await self._prove_dvt(cache_key, cached)
                except Exception:
                    await self._invalidate(cache_key, cached)
                    replaced = True
        try:
            _, _, channel, endpoint_class = await self._get_or_create_service(
                udid, connection_type
            )
        except Exception as error:
            failure = {"success": False, "connected": False, "replaced": replaced,
                       "error": f"{type(error).__name__}: {error}"}
            if isinstance(error, DeviceLanesUnavailable) and error.device_not_visible:
                failure["reason"] = "device_not_visible"
            return failure
        return {"success": True, "connected": True, "replaced": replaced,
                "actual_channel": channel, "endpoint_class": endpoint_class}

    async def connection_status(self, udid: str, connection_type: Optional[str] = None) -> dict:
        """Bounded liveness probe. Never opens a connection.

        A probe that only times out (a slow or briefly stalled link) reports
        not-connected but keeps the connection: closing it would end a held location
        the device may still be honoring. The app decides after repeated failures.
        A probe that fails outright means the connection is dead; it is closed.
        """
        cache_key = self._cache_key(udid, connection_type)
        cached = self._service_cache.get(cache_key)
        if cached is None:
            return {"success": True, "connected": False, "reason": "not connected"}
        try:
            await self._prove_dvt(cache_key, cached)
        except asyncio.TimeoutError:
            return {"success": True, "connected": False,
                    "reason": f"probe timed out after {PROBE_TIMEOUT_SECONDS:g}s"}
        except Exception as error:
            await self._invalidate(cache_key, cached)
            return {"success": True, "connected": False,
                    "reason": f"{type(error).__name__}: {error}"}
        return {"success": True, "connected": True,
                "actual_channel": cached["channel"],
                "endpoint_class": cached["endpoint_class"]}

    async def disconnect_device(self, udid: str, connection_type: Optional[str] = None) -> dict:
        """Close the device connection. This ends any location held over it."""
        cache_key = self._cache_key(udid, connection_type)
        async with self._open_lock(cache_key):
            await self._invalidate(cache_key)
        return {"success": True, "connected": False}

    def _held_provider(self, udid: str, connection_type: Optional[str]):
        """The service provider of the device's open connection (the RSD on RSD lanes,
        the lockdown on usbmux direct), or None. Never opens a connection."""
        cached = self._service_cache.get(self._cache_key(udid, connection_type))
        return None if cached is None else cached.get("provider")

    _DDI_NOT_CONNECTED = {"success": False, "error": "not connected"}
    _DDI_UNSUPPORTED = (
        "Developer Disk Image commands need pymobiledevice3.services.mobile_image_mounter."
        "MobileImageMounterService and auto_mount; the installed pymobiledevice3 lacks the image mounter API"
    )

    async def ddi_status(self, udid: str, connection_type: Optional[str] = None) -> dict:
        """Whether a Developer Disk Image is mounted, asked over the held connection.

        Live 2026-11-03: usbmuxd listed nothing and the phone refused the image mounter
        over its mobdev2 lockdown, while over the remote pairing lane's RSD the image
        mounter answered. "Mounted" means the image mounter lists any image, as
        `mounter list` prints and the app's status check reads it. A failure here is a
        DDI-gate failure only: the device connection stays open.
        """
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}
        provider = self._held_provider(udid, connection_type)
        if provider is None:
            return dict(self._DDI_NOT_CONNECTED)
        if self._image_mounter_service is None:
            return {"success": False, "error": self._DDI_UNSUPPORTED}
        try:
            mounted = await asyncio.wait_for(
                self._list_ddi_images(provider), DDI_STATUS_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            return {"success": False,
                    "error": f"DDI status timed out after {DDI_STATUS_TIMEOUT_SECONDS:g}s"}
        except Exception as error:
            return {"success": False, "error": f"{type(error).__name__}: {error}"}
        return {"success": True, "mounted": mounted}

    async def _list_ddi_images(self, provider) -> bool:
        async with self._image_mounter_service(lockdown=provider) as mounter:
            return len(await mounter.list_images()) > 0

    async def ddi_mount(self, udid: str, connection_type: Optional[str] = None) -> dict:
        """Auto-mount the Developer Disk Image over the held connection, as
        `mounter auto-mount` does (the same library call). An image already mounted is
        what was asked for. Bounded by DDI_MOUNT_TIMEOUT_SECONDS; one mount per device at
        a time. A failure leaves the device connection open.
        """
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}
        if self._held_provider(udid, connection_type) is None:
            return dict(self._DDI_NOT_CONNECTED)
        if self._image_mounter_service is None or self._ddi_auto_mount is None:
            return {"success": False, "error": self._DDI_UNSUPPORTED}
        key = self._cache_key(udid, connection_type)
        lock = self._ddi_mount_locks.setdefault(key, asyncio.Lock())
        mounts_before = self._ddi_mount_successes.get(key, 0)
        # The budget starts once this mount holds the lock (review 2026-11-03 issue 5): it
        # used to include the wait behind another mount, so a second mount timed out while
        # the first mounted the image. The wait is bounded by the holder's own budget.
        async with lock:
            if self._ddi_mount_successes.get(key, 0) != mounts_before:
                # The mount this one queued behind mounted the image: what was asked for.
                return {"success": True, "mounted": True}
            provider = self._held_provider(udid, connection_type)
            if provider is None:
                return dict(self._DDI_NOT_CONNECTED)
            timeout = DDI_MOUNT_TIMEOUT_SECONDS
            try:
                await asyncio.wait_for(self._mount_ddi(key, provider), timeout)
            except asyncio.TimeoutError:
                return {"success": False, "error": f"DDI mount timed out after {timeout:g}s"}
            except Exception as error:
                already = self._already_mounted_error
                if already is None or not isinstance(error, already):
                    return {"success": False, "error": f"{type(error).__name__}: {error}"}
            self._ddi_mount_successes[key] = self._ddi_mount_successes.get(key, 0) + 1
        return {"success": True, "mounted": True}

    async def _mount_ddi(self, key: str, provider) -> None:
        if self._ddi_prefetch is not None:
            # Upstream downloads the image synchronously inside auto_mount; doing it first
            # in a worker thread keeps this helper answering other commands. A timeout
            # cancels only this coroutine, never the thread: a download still running from
            # an earlier attempt is awaited, not started a second time beside it into the
            # same cache (review 2026-11-03 issue 11).
            prefetch = self._ddi_prefetch_tasks.get(key)
            if prefetch is None or prefetch.done():
                prefetch = asyncio.ensure_future(asyncio.to_thread(self._ddi_prefetch, provider))
                # Retrieve a failure nobody awaits any more (its waiter timed out).
                prefetch.add_done_callback(lambda done: done.cancelled() or done.exception())
                self._ddi_prefetch_tasks[key] = prefetch
            await asyncio.shield(prefetch)
        await self._ddi_auto_mount(provider)

    async def _open_userspace_tunnel_cli_exact(
        self, udid: str, cache_key: str,
    ) -> Tuple[any, any, str, str]:
        """Lane 1 — the CLI's proven construction, verbatim (live 2026-10-31):
        ``UserspaceRsdTunnel(serial, autopair=True, remotepairing_fallback=False)``
        established BEFORE any usbmux/lockdown attempt in this process."""
        stack = AsyncExitStack()
        try:
            tunnel = self._userspace_tunnel_factory(
                serial=udid, autopair=True, remotepairing_fallback=False)
            async with _USBMUX_PROVIDER_SWAP_LOCK:
                rsd = await tunnel.aopen()
            stack.push_async_callback(tunnel.aclose)
            dvt = await stack.enter_async_context(self._dvt_module(rsd))
            location = await stack.enter_async_context(self._location_module(dvt))
            channel = "userspaceRSD"
            endpoint_class = "remoteServiceDiscovery"
            self._service_cache[cache_key] = {
                "stack": stack,
                "provider": rsd,
                "dvt": dvt,
                "location": location,
                "channel": channel,
                "endpoint_class": endpoint_class,
            }
            return dvt, location, channel, endpoint_class
        except BaseException:
            await stack.aclose()
            raise

    async def _open_usbmux_direct(
        self, udid: str, cache_key: str, connection_type: Optional[str]
    ) -> Tuple[any, any, str, str]:
        """Open DVT over a direct usbmux lockdown — the CLI's first attempt.

        Raises InvalidServiceError / RSDRequiredError unchanged when the device is
        reachable but the iOS 17+ developer command needs a tunnel (the same signal
        the CLI uses to retry over its no-root userspace tunnel).
        """
        stack = AsyncExitStack()
        try:
            lockdown_arguments = {"serial": udid}
            if connection_type is not None:
                lockdown_arguments["connection_type"] = connection_type
            provider = await self._lockdown_usb(**lockdown_arguments)
            close = getattr(provider, "close", None)
            if close is not None:
                stack.push_async_callback(close)

            dvt = await stack.enter_async_context(self._dvt_module(provider))
            location = await stack.enter_async_context(self._location_module(dvt))
            channel = "usbmuxDirect"
            endpoint_class = "direct"
            self._service_cache[cache_key] = {
                "stack": stack,
                "provider": provider,
                "dvt": dvt,
                "location": location,
                "channel": channel,
                "endpoint_class": endpoint_class,
            }
            return dvt, location, channel, endpoint_class
        except BaseException:
            await stack.aclose()
            raise

    async def _open_preferred_rsd(
        self, udid: str, cache_key: str
    ) -> Tuple[any, any, str, str]:
        """Open a capability-selected no-root RSD provider and report its backend.

        PreferredRsdTunnel implements the same chain the CLI's default fallback uses:
        the in-process no-root userspace tunnel first, the native remoted tunnel on
        macOS when the userspace tunnel cannot serve the device (iOS 17.0-17.3).
        """
        stack = AsyncExitStack()
        try:
            tunnel = self._preferred_tunnel_factory(serial=udid)
            # Its userspace backend reads the same module global the mobdev2 lane swaps.
            async with _USBMUX_PROVIDER_SWAP_LOCK:
                provider = await tunnel.aopen()
            stack.push_async_callback(tunnel.aclose)
            handle_name = type(getattr(tunnel, "_handle", None)).__name__
            channels = {
                "NativeRemotedTunnel": "nativeRSD",
                "UserspaceRsdTunnel": "userspaceRSD",
            }
            channel = channels.get(handle_name)
            if channel is None:
                raise RuntimeError(f"Unsupported preferred RSD backend: {handle_name}")

            dvt = await stack.enter_async_context(self._dvt_module(provider))
            location = await stack.enter_async_context(self._location_module(dvt))
            endpoint_class = "remoteServiceDiscovery"
            self._service_cache[cache_key] = {
                "stack": stack,
                "provider": provider,
                "dvt": dvt,
                "location": location,
                "channel": channel,
                "endpoint_class": endpoint_class,
            }
            return dvt, location, channel, endpoint_class
        except asyncio.CancelledError:
            await stack.aclose()
            raise
        except Exception:
            await stack.aclose()
            raise

    async def _find_mobdev2_lockdown(self, udid: str):
        """Return the paired mobdev2 (Bonjour, TCP) lockdown for `udid`.

        Raises Mobdev2DeviceNotFoundError when Bonjour does not see a paired phone,
        and Mobdev2BrowseError when the browse itself fails (it observed nothing).
        """
        try:
            found = await self._browse_mobdev2_lockdown(udid)
        except OSError as error:
            raise Mobdev2BrowseError(f"{type(error).__name__}: {error}") from error
        if found is None:
            raise Mobdev2DeviceNotFoundError(
                f"mobdev2 Bonjour found no paired lockdown for udid {udid} "
                f"within {MOBDEV2_BROWSE_TIMEOUT_SECONDS:g}s"
            )
        return found

    async def _browse_mobdev2_lockdown(self, udid: str):
        found = None
        # only_paired: an unpaired lockdown cannot open CoreDeviceProxy, and its
        # failure would read as "needs iOS 17.4+". It is not the phone we paired.
        browse = self._mobdev2_lockdowns(
            udid=udid, only_paired=True, timeout=MOBDEV2_BROWSE_TIMEOUT_SECONDS)
        try:
            async for _address, lockdown in browse:
                if getattr(lockdown, "paired", True) is False:
                    await _close_quietly(lockdown)
                    continue
                found = lockdown
                break
        finally:
            try:
                await browse.aclose()
            except BaseException:
                if found is not None:
                    await _close_quietly(found)
                raise
        return found

    @staticmethod
    def _swap_missed(cause: Optional[BaseException] = None,
                     global_name: str = "create_using_usbmux",
                     served: str = "the mobdev2 lockdown") -> LaneUnsupportedError:
        message = (
            f"pymobiledevice3 no longer reads userspace_tunnel.{global_name}: "
            f"the userspace tunnel opened without asking it for {served}"
        )
        if cause is not None:
            message += f" (the open failed with {type(cause).__name__}: {cause})"
        return LaneUnsupportedError(message)

    @staticmethod
    def _is_pre_provider_failure(error: BaseException) -> bool:
        """An upstream error raised before the open asked for its lockdown, such as
        the one-userspace-tunnel-per-process guard: upstream's own verdict, not drift.
        A usbmux lookup failure is excluded: only the real usbmux raises it, so the
        open dialed usbmux instead of reading the swap."""
        names = _class_names(error)
        return _UPSTREAM_BASE_ERROR in names and not (names & _USBMUX_LOOKUP_ERRORS)

    async def _open_mobdev2(self, udid: str, cache_key: str) -> Tuple[any, any, str, str]:
        """The mobdev2 lane — usbmuxd-free (proven live 2026-11-01, read-only): mobdev2 Bonjour
        lockdown -> CoreDeviceProxy userspace tunnel -> RSD -> DVT.

        UserspaceRsdTunnel takes its lockdown from the module-global
        ``create_using_usbmux`` and has no parameter for another one, so for this one
        open that global returns the Bonjour lockdown. The swap holds
        _USBMUX_PROVIDER_SWAP_LOCK (every userspace tunnel open does) and the original
        is restored in ``finally``, also on cancellation. The substitute records that
        it served the UDID: if the open ends without asking for it, pymobiledevice3
        has stopped reading that global, and the lane reports itself unsupported
        instead of a visibility gap (rolling-latest drift), keeping the open's own
        error in the message. A pymobiledevice3 error from before the provider call
        (its one-tunnel-per-process guard) is upstream's verdict and is re-raised as is.
        """
        browse = self._mobdev2_lockdowns
        module = self._userspace_tunnel_module
        if browse is None or module is None or not hasattr(module, "create_using_usbmux"):
            raise LaneUnsupportedError(
                "mobdev2 lane needs pymobiledevice3.lockdown.get_mobdev2_lockdowns and "
                "pymobiledevice3.remote.userspace_tunnel.create_using_usbmux; "
                "the installed pymobiledevice3 lacks one"
            )
        stack = AsyncExitStack()
        try:
            lockdown = await self._find_mobdev2_lockdown(udid)
            # Backstop owner of the lockdown. Once the tunnel has taken it, upstream
            # also closes it (on the tunnel's own exit stack and on every failure
            # path), so this second close is a harmless no-op then. It is the only
            # close when the tunnel never received it (the swap missed, or the open
            # failed before asking for it).
            stack.push_async_callback(_close_quietly, lockdown)
            tunnel = self._userspace_tunnel_factory(
                serial=udid, autopair=True, remotepairing_fallback=False)
            served = False
            async with _USBMUX_PROVIDER_SWAP_LOCK:
                original = module.create_using_usbmux

                async def lockdown_from_mobdev2(serial=None, autopair=True, **kwargs):
                    nonlocal served
                    if serial == udid:
                        served = True
                        return lockdown
                    return await original(serial=serial, autopair=autopair, **kwargs)

                module.create_using_usbmux = lockdown_from_mobdev2
                try:
                    rsd = await tunnel.aopen()
                except Exception as error:
                    if not served and not self._is_pre_provider_failure(error):
                        raise self._swap_missed(error) from error
                    raise
                finally:
                    module.create_using_usbmux = original
            stack.push_async_callback(tunnel.aclose)
            if not served:
                # A tunnel pymobiledevice3 made some other way (real usbmux) is not
                # this lane; close it with the stack.
                raise self._swap_missed()
            dvt = await stack.enter_async_context(self._dvt_module(rsd))
            location = await stack.enter_async_context(self._location_module(dvt))
            channel = "mobdev2RSD"
            endpoint_class = "remoteServiceDiscovery"
            self._service_cache[cache_key] = {
                "stack": stack,
                "provider": rsd,
                "dvt": dvt,
                "location": location,
                "channel": channel,
                "endpoint_class": endpoint_class,
            }
            return dvt, location, channel, endpoint_class
        except BaseException:
            await stack.aclose()
            raise

    _REMOTE_PAIRING_REFRESH_ADVICE = (
        "connect the cable once and press Prepare for Wi-Fi to refresh it"
    )

    def _check_remote_pair_record(self, udid: str) -> None:
        """Raise RemotePairingRecordStaleError unless this Mac holds a RemotePairing
        record for `udid` with the phone's altIRK.

        Reads the records exactly as get_remote_pairing_tunnel_services does (same
        iterator, same key): without the altIRK the browse cannot match the phone's
        advert and returns nothing, which would otherwise read as "not visible".
        Only the key's presence is checked; no record content leaves this function.
        """
        try:
            records = [
                record for identifier, _path, record in self._remote_pair_records()
                if identifier == udid
            ]
        except OSError as error:
            raise RemotePairingRecordStaleError(
                f"could not read this Mac's RemotePairing records ({type(error).__name__}); "
                f"{self._REMOTE_PAIRING_REFRESH_ADVICE}"
            ) from None
        if not records:
            raise RemotePairingRecordStaleError(
                "this Mac has no RemotePairing record for the phone; "
                f"{self._REMOTE_PAIRING_REFRESH_ADVICE}"
            )
        key = self._peer_alt_irk_key
        if not any(isinstance(record, dict) and record.get(key) is not None for record in records):
            raise RemotePairingRecordStaleError(
                "the phone's RemotePairing record predates altIRK, so Bonjour cannot recognize "
                f"the phone at a new Wi-Fi address; {self._REMOTE_PAIRING_REFRESH_ADVICE}"
            )

    @staticmethod
    def _remote_pairing_address_rank(hostname: str) -> int:
        """0: a routable IPv4 address; 1: any other IPv4 (169.254/16 link-local, used by
        the USB link); 2: IPv6 or anything else (often a USB-link fe80:: address)."""
        try:
            address = ipaddress.ip_address(hostname)
        except ValueError:
            return 2
        if address.version != 4:
            return 2
        if address.is_link_local or address.is_loopback or address.is_unspecified:
            return 1
        return 0

    @classmethod
    def _preferred_remote_pairing_service(cls, services):
        """The advertised service to tunnel over: the first with the best address rank."""
        best = None
        for service in services:
            rank = cls._remote_pairing_address_rank(str(getattr(service, "hostname", "") or ""))
            if best is None or rank < best[0]:
                best = (rank, service)
        return None if best is None else best[1]

    @staticmethod
    async def _close_services(services) -> None:
        """Close every service, also when cancelled part-way; re-raise afterwards."""
        pending = None
        for service in services:
            try:
                await _close_quietly(service)
            except BaseException as error:  # CancelledError: keep closing the rest.
                pending = pending or error
        if pending is not None:
            raise pending

    async def _find_remote_pairing_service(self, udid: str):
        """Return one connected RemotePairing service for `udid`, closing the others.

        Raises RemotePairingDeviceNotFoundError when no advert accepted this Mac's
        pairing (none matched, or upstream skipped every address of a matching one), and
        RemotePairingBrowseError when the browse itself fails (it observed nothing).
        """
        try:
            services = await self._remote_pairing_services(
                udid=udid, bonjour_timeout=REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS)
        except OSError as error:
            raise RemotePairingBrowseError(f"{type(error).__name__}: {error}") from error
        services = list(services or [])
        chosen = None
        try:
            chosen = self._preferred_remote_pairing_service(services)
        finally:
            unused = [service for service in services if service is not chosen]
            try:
                await self._close_services(unused)
            except BaseException:
                if chosen is not None:
                    await self._close_services([chosen])
                raise
        if chosen is None:
            raise RemotePairingDeviceNotFoundError(
                "RemotePairing Bonjour found no advert that accepted this Mac's pairing for the "
                f"phone within {REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS:g}s (it may be off this "
                "network, or its pairing may need a refresh)"
            )
        return chosen

    async def _find_remote_pairing_service_bounded(self, udid: str):
        """_find_remote_pairing_service within REMOTE_PAIRING_LANE_TIMEOUT_SECONDS.

        On timeout the find is cancelled; it closes every service it already holds
        (see _close_services) before RemotePairingTimeoutError is raised. Services that
        upstream connected but had not yet returned are upstream's to close.
        """
        try:
            return await asyncio.wait_for(
                self._find_remote_pairing_service(udid), REMOTE_PAIRING_LANE_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            # The find wraps every OSError (TimeoutError included) from the browse in
            # RemotePairingBrowseError, so a TimeoutError here is this bound.
            raise RemotePairingTimeoutError(
                "RemotePairing browse and pair-verify did not finish within "
                f"{REMOTE_PAIRING_LANE_TIMEOUT_SECONDS:g}s"
            ) from None

    async def _open_remote_pairing(self, udid: str, cache_key: str) -> Tuple[any, any, str, str]:
        """Remote pairing lane — usbmuxd-free at any Wi-Fi address (proven live
        2026-11-02, read-only): RemotePairing Bonjour advert matched by the record's
        altIRK -> pair-verified RemotePairingTunnelService -> userspace tunnel -> RSD -> DVT.

        UserspaceRsdTunnel picks its provider through the module-global
        ``_create_no_root_tunnel_provider`` and has no parameter for another one, so for
        this one open that global returns the chosen service. As in the mobdev2 lane, the
        swap holds _USBMUX_PROVIDER_SWAP_LOCK, is restored in ``finally`` (also on
        cancellation), and reports drift when the open ends without asking for it.
        pymobiledevice3 allows one userspace tunnel per process; its guard raises before
        the provider call and is re-raised as is.
        """
        find = self._remote_pairing_services
        module = self._userspace_tunnel_module
        if (find is None or self._remote_pair_records is None or self._peer_alt_irk_key is None
                or module is None or not hasattr(module, "_create_no_root_tunnel_provider")):
            raise LaneUnsupportedError(
                "remote pairing lane needs pymobiledevice3.remote.tunnel_service."
                "get_remote_pairing_tunnel_services and PEER_ALT_IRK_KEY, "
                "pymobiledevice3.pair_records.iter_remote_pair_records_by_identifier and "
                "pymobiledevice3.remote.userspace_tunnel._create_no_root_tunnel_provider; "
                "the installed pymobiledevice3 lacks one"
            )
        self._check_remote_pair_record(udid)
        stack = AsyncExitStack()
        try:
            service = await self._find_remote_pairing_service_bounded(udid)
            # Backstop owner of the service. Once the tunnel has taken it, upstream also
            # closes it (its exit stack, every failure path); a second close is a no-op.
            stack.push_async_callback(_close_quietly, service)
            tunnel = self._userspace_tunnel_factory(
                serial=udid, autopair=True, remotepairing_fallback=False)
            served = False
            async with _USBMUX_PROVIDER_SWAP_LOCK:
                original = module._create_no_root_tunnel_provider

                async def provider_from_remote_pairing(
                    serial=None, autopair=True, remotepairing_fallback=True, *args, **kwargs
                ):
                    nonlocal served
                    if serial == udid:
                        served = True
                        return service, None
                    return await original(serial, autopair, remotepairing_fallback, *args, **kwargs)

                module._create_no_root_tunnel_provider = provider_from_remote_pairing
                try:
                    rsd = await tunnel.aopen()
                except Exception as error:
                    if not served and not self._is_pre_provider_failure(error):
                        raise self._swap_missed(
                            error, "_create_no_root_tunnel_provider", "the RemotePairing service"
                        ) from error
                    raise
                finally:
                    module._create_no_root_tunnel_provider = original
            stack.push_async_callback(tunnel.aclose)
            if not served:
                raise self._swap_missed(
                    None, "_create_no_root_tunnel_provider", "the RemotePairing service")
            dvt = await stack.enter_async_context(self._dvt_module(rsd))
            location = await stack.enter_async_context(self._location_module(dvt))
            channel = "remotePairingRSD"
            endpoint_class = "remoteServiceDiscovery"
            self._service_cache[cache_key] = {
                "stack": stack,
                "provider": rsd,
                "dvt": dvt,
                "location": location,
                "channel": channel,
                "endpoint_class": endpoint_class,
            }
            return dvt, location, channel, endpoint_class
        except BaseException:
            await stack.aclose()
            raise

    async def _invalidate(self, cache_key: str, expected: Optional[dict] = None) -> None:
        """Close the device connection. With `expected`, close it only if it is still
        the connection that failed: a late failure on an old connection must never
        close a newer one."""
        cached = self._service_cache.get(cache_key)
        if cached is None or (expected is not None and cached is not expected):
            return
        self._service_cache.pop(cache_key, None)
        try:
            await cached["stack"].aclose()
        except Exception:
            pass
        if self.on_connection_closed is not None:
            try:
                self.on_connection_closed(cache_key)
            except Exception:
                pass

    async def set_location(
        self,
        lat: float,
        lng: float,
        udid: str,
        rsd_address: Optional[str] = None,
        rsd_port: Optional[int] = None,
        connection_type: Optional[str] = None,
    ) -> dict:
        """Set simulated location and acknowledge the channel that applied it."""
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}

        # rsd_address / rsd_port are accepted for wire compatibility and ignored:
        # the helper owns the only device connection.
        cache_key = self._cache_key(udid, connection_type)
        used = None
        try:
            _, location, channel, endpoint_class = await self._get_or_create_service(
                udid, connection_type
            )
            used = self._service_cache.get(cache_key)
            await asyncio.wait_for(location.set(lat, lng), DEVICE_OPERATION_TIMEOUT_SECONDS)
            return {
                "success": True,
                "actual_channel": channel,
                "endpoint_class": endpoint_class,
            }
        except Exception as error:
            if used is not None:
                await self._invalidate(cache_key, used)
            return {"success": False, "error": f"{type(error).__name__}: {error}"}

    async def clear_location(
        self,
        udid: str,
        rsd_address: Optional[str] = None,
        rsd_port: Optional[int] = None,
        connection_type: Optional[str] = None,
    ) -> dict:
        """Clear simulated location and acknowledge the channel that reset it."""
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}

        cache_key = self._cache_key(udid, connection_type)
        used = None
        try:
            _, location, channel, endpoint_class = await self._get_or_create_service(
                udid, connection_type
            )
            used = self._service_cache.get(cache_key)
            await asyncio.wait_for(location.clear(), DEVICE_OPERATION_TIMEOUT_SECONDS)
            return {
                "success": True,
                "actual_channel": channel,
                "endpoint_class": endpoint_class,
            }
        except Exception as error:
            if used is not None:
                await self._invalidate(cache_key, used)
            return {"success": False, "error": f"{type(error).__name__}: {error}"}

    async def close_all(self) -> None:
        """Close all cached async connections."""
        cached_services = list(self._service_cache.values())
        self._service_cache.clear()
        for cached in cached_services:
            try:
                await cached["stack"].aclose()
            except Exception:
                pass


def validate_coordinate(value: any) -> Optional[float]:
    """Validate and convert coordinate value."""
    if value is None:
        return None
    try:
        coord = float(value)
        if coord != coord:  # NaN check
            return None
        return coord
    except (TypeError, ValueError):
        return None


def validate_request(request: dict) -> Tuple[bool, str]:
    """Validate incoming request structure."""
    if not isinstance(request, dict):
        return False, "Request must be a JSON object"
    
    cmd = request.get("cmd")
    if not cmd:
        return False, "Missing 'cmd' field"
    
    if cmd not in (
        "set_location", "clear_location", "ping", "quit",
        "connect_device", "connection_status", "disconnect_device",
        "ddi_status", "ddi_mount",
    ):
        return False, f"Unknown command: {cmd}"

    request_id = request.get("request_id")
    if not request_id or not isinstance(request_id, str):
        return False, "Missing or invalid 'request_id' field"
    session_generation = request.get("session_generation")
    if not isinstance(session_generation, int) or session_generation < 0:
        return False, "Missing or invalid 'session_generation' field"
    
    if cmd == "set_location":
        lat = validate_coordinate(request.get("lat"))
        lng = validate_coordinate(request.get("lng"))
        if lat is None or lng is None:
            return False, "Invalid coordinates"
        if not (-90 <= lat <= 90):
            return False, "Latitude must be between -90 and 90"
        if not (-180 <= lng <= 180):
            return False, "Longitude must be between -180 and 180"
        
        udid = request.get("udid")
        if not udid or not isinstance(udid, str):
            return False, "Missing or invalid 'udid' field"
    
    if cmd in (
        "clear_location", "connect_device", "connection_status", "disconnect_device",
        "ddi_status", "ddi_mount",
    ):
        udid = request.get("udid")
        if not udid or not isinstance(udid, str):
            return False, "Missing or invalid 'udid' field"
    
    return True, ""


async def process_command(connection: DeviceConnection, request: dict) -> dict:
    """Process a single command and return response."""
    cmd = request.get("cmd")

    if cmd == "ping":
        return {"success": True, "message": "pong"}

    if cmd == "quit":
        global _shutdown_requested
        _shutdown_requested = True
        if _shutdown_event is not None:
            _shutdown_event.set()
        return {"success": True, "message": "shutting down"}

    if cmd == "set_location":
        return await connection.set_location(
            lat=float(request["lat"]),
            lng=float(request["lng"]),
            udid=request["udid"],
            rsd_address=request.get("rsd_address"),
            rsd_port=request.get("rsd_port"),
            connection_type=request.get("connection_type"),
        )

    if cmd in ("connect_device", "connection_status", "disconnect_device", "ddi_status", "ddi_mount"):
        handler = getattr(connection, cmd)
        return await handler(
            udid=request["udid"],
            connection_type=request.get("connection_type"),
        )

    if cmd == "clear_location":
        return await connection.clear_location(
            udid=request["udid"],
            rsd_address=request.get("rsd_address"),
            rsd_port=request.get("rsd_port"),
            connection_type=request.get("connection_type"),
        )

    return {"success": False, "error": "Unknown command"}


async def _stdin_reader():
    """Read stdin while allowing signals to cancel a pending line read."""
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    transport, _ = await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    try:
        while not _shutdown_requested:
            read_task = asyncio.create_task(reader.readline())
            shutdown_task = asyncio.create_task(_shutdown_event.wait())
            done, _ = await asyncio.wait(
                {read_task, shutdown_task},
                return_when=asyncio.FIRST_COMPLETED,
            )

            if shutdown_task in done:
                read_task.cancel()
                await asyncio.gather(read_task, return_exceptions=True)
                break

            shutdown_task.cancel()
            await asyncio.gather(shutdown_task, return_exceptions=True)
            line = read_task.result()
            if not line:
                break
            yield line.decode() if isinstance(line, bytes) else line
    finally:
        transport.close()


async def _process_commands(connection):
    """Process commands from stdin in ordered sequence."""
    async for line in _stdin_reader():
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            response = {"success": False, "error": f"Invalid JSON: {error}"}
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
            continue

        valid, error_msg = validate_request(request)
        if not valid:
            response = {"success": False, "error": error_msg, "code": "INVALID_REQUEST"}
            if isinstance(request, dict):
                if isinstance(request.get("request_id"), str):
                    response["request_id"] = request["request_id"]
                if isinstance(request.get("session_generation"), int):
                    response["session_generation"] = request["session_generation"]
        else:
            response = await process_command(connection, request)
            response["request_id"] = request["request_id"]
            response["session_generation"] = request["session_generation"]

        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


def _load_auth_token(token_path: str) -> str:
    """Load a non-empty token from an owner-only regular file."""
    token_stat = os.stat(token_path, follow_symlinks=False)
    if not stat.S_ISREG(token_stat.st_mode):
        raise RuntimeError("Helper token path must be a regular file")
    if token_stat.st_uid != os.getuid() or token_stat.st_mode & 0o077:
        raise RuntimeError("Helper token file must be owner-only")
    with open(token_path, "r", encoding="utf-8") as token_file:
        token = token_file.read().strip()
    if not token:
        raise RuntimeError("Helper token file is empty")
    return token


def _prepare_socket_path(socket_path: str) -> None:
    """Validate the private socket directory and remove only an owned stale socket."""
    directory = os.path.dirname(socket_path) or "."
    directory_stat = os.stat(directory, follow_symlinks=False)
    if not stat.S_ISDIR(directory_stat.st_mode):
        raise RuntimeError("Helper socket parent must be a directory")
    if directory_stat.st_uid != os.getuid() or directory_stat.st_mode & 0o077:
        raise RuntimeError("Helper socket directory must be owner-only")
    try:
        existing = os.lstat(socket_path)
    except FileNotFoundError:
        return
    if existing.st_uid != os.getuid() or not stat.S_ISSOCK(existing.st_mode):
        raise RuntimeError("Refusing to replace a non-socket or unowned helper path")
    os.unlink(socket_path)


def _sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_helper_record(record_path: str, socket_path: str, auth_token: str, helper_id: str) -> None:
    """Atomically publish non-secret identity evidence for secure adoption."""
    record = {
        "protocol_version": 1,
        "helper_id": helper_id,
        "pid": os.getpid(),
        "socket_path": socket_path,
        "python_path": os.path.realpath(sys.executable),
        "python_sha256": _sha256_file(sys.executable),
        "bridge_path": os.path.realpath(__file__),
        "bridge_sha256": _sha256_file(__file__),
        "token_sha256": hashlib.sha256(auth_token.encode()).hexdigest(),
        "active_sessions": [],
        "recent_results": [],
    }
    temporary_path = f"{record_path}.{uuid.uuid4().hex}.tmp"
    descriptor = os.open(temporary_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
            json.dump(record, destination, sort_keys=True)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary_path, record_path)
        os.chmod(record_path, 0o600)
    finally:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass


def _read_helper_record(record_path: str) -> dict:
    record_stat = os.stat(record_path, follow_symlinks=False)
    if not stat.S_ISREG(record_stat.st_mode):
        raise RuntimeError("Helper record path must be a regular file")
    if record_stat.st_uid != os.getuid() or record_stat.st_mode & 0o077:
        raise RuntimeError("Helper record must be owner-only")
    with open(record_path, "r", encoding="utf-8") as source:
        return json.load(source)


def _replace_helper_record(record_path: str, record: dict) -> None:
    temporary_path = f"{record_path}.{uuid.uuid4().hex}.tmp"
    descriptor = os.open(temporary_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
            json.dump(record, destination, sort_keys=True)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary_path, record_path)
        os.chmod(record_path, 0o600)
    finally:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass


def _device_id_digest(request: dict) -> str:
    return hashlib.sha256(request["udid"].encode()).hexdigest()


def _record_location_result(record_path: str, request: dict, response: dict) -> None:
    """Atomically persist bounded provider results and active-session ownership."""
    record = _read_helper_record(record_path)
    device_digest = _device_id_digest(request)
    completed_at = time.time()

    if response.get("success") and request["cmd"] == "set_location":
        session = {
            "device_id_sha256": device_digest,
            "request_id": request["request_id"],
            "session_generation": request["session_generation"],
            "physical_transport": request.get("connection_type", "USB"),
            "actual_channel": response["actual_channel"],
            "endpoint_class": response["endpoint_class"],
            "coordinate": {
                "latitude": request["lat"],
                "longitude": request["lng"],
            },
            "acknowledged_at": completed_at,
        }
        sessions = [
            existing for existing in record.get("active_sessions", [])
            if existing.get("device_id_sha256") != device_digest
        ]
        sessions.append(session)
        record["active_sessions"] = sessions
    elif response.get("success") and request["cmd"] == "clear_location":
        record["active_sessions"] = [
            existing for existing in record.get("active_sessions", [])
            if existing.get("device_id_sha256") != device_digest
        ]

    result = {
        "cmd": request["cmd"],
        "device_id_sha256": device_digest,
        "request_id": request["request_id"],
        "session_generation": request["session_generation"],
        "success": bool(response.get("success")),
        "error": response.get("error"),
        "code": response.get("code"),
        "physical_transport": request.get("connection_type", "USB"),
        "actual_channel": response.get("actual_channel"),
        "endpoint_class": response.get("endpoint_class"),
        "coordinate": (
            {"latitude": request["lat"], "longitude": request["lng"]}
            if request["cmd"] == "set_location" else None
        ),
        "completed_at": completed_at,
    }
    recent_results = [
        existing for existing in record.get("recent_results", [])
        if not (
            existing.get("request_id") == request["request_id"]
            and existing.get("session_generation") == request["session_generation"]
        )
    ]
    recent_results.append(result)
    record["recent_results"] = recent_results[-64:]
    _replace_helper_record(record_path, record)


def _forget_device_sessions(record_path: str, udid: str) -> None:
    """Drop a device's held session: its connection closed, so the location ended."""
    record = _read_helper_record(record_path)
    digest = hashlib.sha256(udid.encode()).hexdigest()
    remaining = [
        session for session in record.get("active_sessions", [])
        if session.get("device_id_sha256") != digest
    ]
    if len(remaining) != len(record.get("active_sessions", [])):
        record["active_sessions"] = remaining
        _replace_helper_record(record_path, record)


def _record_acknowledged_application(record_path: str, request: dict, response: dict) -> None:
    _record_location_result(record_path, request, response)


def _record_acknowledged_clear(record_path: str, request: dict, response: dict) -> None:
    _record_location_result(record_path, request, response)


async def _handle_socket_client(
    reader, writer, connection, auth_token, helper_id, record_path, clients
):
    """Serve ordered authenticated NDJSON requests for one reconnectable client."""
    current_task = asyncio.current_task()
    if current_task is not None:
        clients.add(current_task)
    try:
        while not _shutdown_requested:
            line = await reader.readline()
            if not line:
                break
            request = None
            try:
                request = json.loads(line.decode())
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                response = {"success": False, "error": f"Invalid JSON: {error}"}
            else:
                supplied_token = request.get("auth_token") if isinstance(request, dict) else None
                if not isinstance(supplied_token, str) or not hmac.compare_digest(supplied_token, auth_token):
                    response = {
                        "success": False,
                        "error": "Invalid helper authentication",
                        "code": "UNAUTHORIZED",
                    }
                else:
                    request = dict(request)
                    request.pop("auth_token", None)
                    valid, error_msg = validate_request(request)
                    if not valid:
                        response = {"success": False, "error": error_msg, "code": "INVALID_REQUEST"}
                    else:
                        response = await process_command(connection, request)
                        if isinstance(request.get("request_id"), str):
                            response["request_id"] = request["request_id"]
                        if isinstance(request.get("session_generation"), int):
                            response["session_generation"] = request["session_generation"]
                        if request.get("cmd") in {"set_location", "clear_location"}:
                            try:
                                _record_location_result(record_path, request, response)
                            except Exception as record_error:
                                response = {
                                    "success": False,
                                    "error": f"Failed to persist helper session ownership: {record_error}",
                                    "code": "OWNERSHIP_RECORD_FAILED",
                                    "request_id": request.get("request_id"),
                                    "session_generation": request.get("session_generation"),
                                    "location_may_be_active": request["cmd"] == "set_location",
                                    "ownership_record_may_be_stale": True,
                                }
                    if isinstance(request, dict) and isinstance(request.get("request_id"), str):
                        response["request_id"] = request["request_id"]
                    if isinstance(request, dict) and isinstance(request.get("session_generation"), int):
                        response["session_generation"] = request["session_generation"]
            response["helper_id"] = helper_id
            writer.write((json.dumps(response) + "\n").encode())
            await writer.drain()
            if isinstance(request, dict) and request.get("cmd") == "quit" and response.get("success"):
                break
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (BrokenPipeError, ConnectionResetError):
            pass
        if current_task is not None:
            clients.discard(current_task)


async def _serve_unix_socket(
    connection, socket_path: str, auth_token: str, record_path: str, helper_id: str
) -> None:
    """Serve authenticated clients until explicit quit or a shutdown signal."""
    _prepare_socket_path(socket_path)
    clients = set()

    async def client_connected(reader, writer):
        await _handle_socket_client(
            reader, writer, connection, auth_token, helper_id, record_path, clients
        )

    server = await asyncio.start_unix_server(client_connected, path=socket_path)
    os.chmod(socket_path, 0o600)
    _write_helper_record(record_path, socket_path, auth_token, helper_id)
    sys.stdout.write(json.dumps({
        "ready": True, "transport": "unix_socket", "helper_id": helper_id
    }) + "\n")
    sys.stdout.flush()
    try:
        async with server:
            await _shutdown_event.wait()
    finally:
        server.close()
        await server.wait_closed()
        if clients:
            _, pending = await asyncio.wait(tuple(clients), timeout=1.0)
            for task in pending:
                task.cancel()
            if pending:
                await asyncio.gather(*tuple(pending), return_exceptions=True)
        for owned_path, expected_type in (
            (socket_path, "socket"),
            (record_path, "regular"),
        ):
            try:
                existing = os.lstat(owned_path)
                is_expected_type = (
                    stat.S_ISSOCK(existing.st_mode)
                    if expected_type == "socket"
                    else stat.S_ISREG(existing.st_mode)
                )
                if existing.st_uid == os.getuid() and is_expected_type:
                    os.unlink(owned_path)
            except FileNotFoundError:
                pass


def main():
    """Run stdin compatibility mode or the authenticated managed-helper server."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket")
    parser.add_argument("--token-file")
    parser.add_argument("--record-file")
    args = parser.parse_args()
    socket_mode_arguments = (args.socket, args.token_file, args.record_file)
    if any(socket_mode_arguments) and not all(socket_mode_arguments):
        parser.error("--socket, --token-file, and --record-file must be supplied together")

    global _shutdown_requested, _shutdown_event, _event_loop
    _shutdown_requested = False
    connection = DeviceConnection()
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    _event_loop = loop
    _shutdown_event = asyncio.Event()

    try:
        if args.socket:
            auth_token = _load_auth_token(args.token_file)
            helper_id = str(uuid.uuid4())
            record_file = args.record_file

            def forget_sessions(udid):
                try:
                    _forget_device_sessions(record_file, udid)
                except Exception:
                    pass

            connection.on_connection_closed = forget_sessions
            loop.run_until_complete(_serve_unix_socket(
                connection, args.socket, auth_token, args.record_file, helper_id
            ))
        else:
            sys.stdout.write(json.dumps({"ready": True}) + "\n")
            sys.stdout.flush()
            loop.run_until_complete(_process_commands(connection))
    except Exception as error:
        response = {"success": False, "error": f"Internal error: {error}"}
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()
    finally:
        loop.run_until_complete(connection.close_all())
        if args.record_file:
            try:
                record_stat = os.lstat(args.record_file)
                if record_stat.st_uid == os.getuid() and stat.S_ISREG(record_stat.st_mode):
                    os.unlink(args.record_file)
            except FileNotFoundError:
                pass
        _shutdown_event = None
        _event_loop = None
        loop.close()


if __name__ == "__main__":
    main()
