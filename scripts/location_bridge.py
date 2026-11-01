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

# pymobiledevice3 raises these when usbmux does not list the device right now. An
# idle Wi-Fi phone drops out of usbmux for seconds to minutes (live 2026-11-01), so
# when every lane says this, the phone is not visible yet - not broken.
_DEVICE_ABSENT_ERRORS = frozenset({"DeviceNotFoundError", "NoDeviceConnectedError"})


class DeviceLanesUnavailable(RuntimeError):
    """Every connection lane failed; carries each lane's own error, in order."""

    def __init__(self, failures):
        self.failures = list(failures)
        self.device_not_visible = bool(self.failures) and all(
            type(error).__name__ in _DEVICE_ABSENT_ERRORS for _, error in self.failures
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
            from pymobiledevice3.exceptions import InvalidServiceError, RSDRequiredError

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
        """
        if connection_type not in (None, "USB", "Network"):
            raise ValueError("connection_type must be USB or Network")
        cache_key = self._cache_key(udid, connection_type)
        async with self._open_lock(cache_key):
            cached = self._service_cache.get(cache_key)
            if cached is None:
                await asyncio.wait_for(
                    self._open_lanes(udid, cache_key, connection_type),
                    CONNECT_TIMEOUT_SECONDS,
                )
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
        self, udid: str, cache_key: str, connection_type: Optional[str]
    ) -> None:
        # Each lane's own error is kept: reporting only the last lane's hid why the
        # primary lane failed (the GUI always showed the usbmux lane's message).
        failures = []
        try:
            await self._open_userspace_tunnel_cli_exact(udid, cache_key)
            return
        except Exception as error:
            failures.append(("userspace tunnel", error))

        try:
            await self._open_usbmux_direct(udid, cache_key, connection_type)
            return
        except Exception as error:
            failures.append(("usbmux direct", error))

        try:
            await self._open_preferred_rsd(udid, cache_key)
            return
        except Exception as error:
            failures.append(("preferred RSD", error))
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
            rsd = await tunnel.aopen()
            stack.push_async_callback(tunnel.aclose)
            dvt = await stack.enter_async_context(self._dvt_module(rsd))
            location = await stack.enter_async_context(self._location_module(dvt))
            channel = "userspaceRSD"
            endpoint_class = "remoteServiceDiscovery"
            self._service_cache[cache_key] = {
                "stack": stack,
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
    
    if cmd in ("clear_location", "connect_device", "connection_status", "disconnect_device"):
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

    if cmd in ("connect_device", "connection_status", "disconnect_device"):
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
