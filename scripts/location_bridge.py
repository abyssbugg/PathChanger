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
    - set_location: Set simulated location on device
    - ping: Health check
    - quit: Graceful shutdown

Security:
    - Input validation on all JSON fields
    - No arbitrary command execution
    - Rate limiting handled by Swift layer
"""

import sys
import json
import signal
import traceback
from typing import Optional, Tuple
from contextlib import contextmanager

# Graceful shutdown flag
_shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global _shutdown_requested
    _shutdown_requested = True


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
        self._initialized = False
    
    def _lazy_import(self):
        """Import pymobiledevice3 modules lazily to avoid import errors on startup."""
        if self._initialized:
            return True
            
        try:
            from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
            from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
            from pymobiledevice3.lockdown import create_using_usbmux, create_using_tcp
            from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
            
            self._dvt_module = DvtSecureSocketProxyService
            self._location_module = LocationSimulation
            self._lockdown_usb = create_using_usbmux
            self._lockdown_tcp = create_using_tcp
            self._rsd_module = RemoteServiceDiscoveryService
            self._initialized = True
            return True
        except ImportError as e:
            return False
    
    def _get_or_create_service(self, udid: str, rsd_address: Optional[str], rsd_port: Optional[int]) -> Tuple[any, any]:
        """Get cached DVT service or create new one."""
        cache_key = f"{udid}:{rsd_address}:{rsd_port}"
        
        if cache_key in self._service_cache:
            cached = self._service_cache[cache_key]
            # Check if service is still valid
            try:
                # Test connection by accessing a property
                if cached['dvt'] is not None:
                    return cached['dvt'], cached['location']
            except:
                # Connection dead, remove from cache
                del self._service_cache[cache_key]
        
        # Create new connection
        try:
            if rsd_address and rsd_port:
                # WiFi/tunnel connection via RSD
                rsd = self._rsd_module((rsd_address, rsd_port))
                rsd.connect()
                dvt = self._dvt_module(rsd)
            else:
                # USB connection
                lockdown = self._lockdown_usb(serial=udid)
                dvt = self._dvt_module(lockdown=lockdown)
            
            dvt.perform_handshake()
            location_service = self._location_module(dvt)
            
            self._service_cache[cache_key] = {
                'dvt': dvt,
                'location': location_service,
                'rsd': rsd if rsd_address else None
            }
            
            return dvt, location_service
        except Exception as e:
            raise RuntimeError(f"Failed to connect to device: {str(e)}")
    
    def set_location(self, lat: float, lng: float, udid: str, 
                     rsd_address: Optional[str] = None, 
                     rsd_port: Optional[int] = None) -> dict:
        """Set simulated location on device."""
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}
        
        try:
            dvt, location_service = self._get_or_create_service(udid, rsd_address, rsd_port)
            location_service.simulate_location(lat, lng)
            return {"success": True}
        except Exception as e:
            # Clear cache on error to force reconnection
            cache_key = f"{udid}:{rsd_address}:{rsd_port}"
            if cache_key in self._service_cache:
                del self._service_cache[cache_key]
            return {"success": False, "error": str(e)}
    
    def clear_location(self, udid: str, 
                       rsd_address: Optional[str] = None, 
                       rsd_port: Optional[int] = None) -> dict:
        """Clear simulated location on device."""
        if not self._lazy_import():
            return {"success": False, "error": "pymobiledevice3 not installed"}
        
        try:
            dvt, location_service = self._get_or_create_service(udid, rsd_address, rsd_port)
            location_service.clear_simulated_location()
            return {"success": True}
        except Exception as e:
            # Clear cache on error
            cache_key = f"{udid}:{rsd_address}:{rsd_port}"
            if cache_key in self._service_cache:
                del self._service_cache[cache_key]
            return {"success": False, "error": str(e)}
    
    def close_all(self):
        """Close all cached connections."""
        for cache_key, cached in list(self._service_cache.items()):
            try:
                if cached.get('rsd'):
                    cached['rsd'].close()
                if cached.get('dvt'):
                    cached['dvt'].close()
            except:
                pass
        self._service_cache.clear()


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
    
    if cmd not in ("set_location", "clear_location", "ping", "quit"):
        return False, f"Unknown command: {cmd}"
    
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
    
    if cmd == "clear_location":
        udid = request.get("udid")
        if not udid or not isinstance(udid, str):
            return False, "Missing or invalid 'udid' field"
    
    return True, ""


def process_command(connection: DeviceConnection, request: dict) -> dict:
    """Process a single command and return response."""
    cmd = request.get("cmd")
    
    if cmd == "ping":
        return {"success": True, "message": "pong"}
    
    if cmd == "quit":
        global _shutdown_requested
        _shutdown_requested = True
        return {"success": True, "message": "shutting down"}
    
    if cmd == "set_location":
        return connection.set_location(
            lat=float(request["lat"]),
            lng=float(request["lng"]),
            udid=request["udid"],
            rsd_address=request.get("rsd_address"),
            rsd_port=request.get("rsd_port")
        )
    
    if cmd == "clear_location":
        return connection.clear_location(
            udid=request["udid"],
            rsd_address=request.get("rsd_address"),
            rsd_port=request.get("rsd_port")
        )
    
    return {"success": False, "error": "Unknown command"}


def main():
    """Main event loop - reads commands from stdin, writes responses to stdout."""
    connection = DeviceConnection()
    
    # Signal ready status
    sys.stdout.write(json.dumps({"ready": True}) + "\n")
    sys.stdout.flush()
    
    try:
        while not _shutdown_requested:
            try:
                line = sys.stdin.readline()
                if not line:
                    # EOF received
                    break
                
                line = line.strip()
                if not line:
                    continue
                
                # Parse JSON request
                try:
                    request = json.loads(line)
                except json.JSONDecodeError as e:
                    response = {"success": False, "error": f"Invalid JSON: {str(e)}"}
                    sys.stdout.write(json.dumps(response) + "\n")
                    sys.stdout.flush()
                    continue
                
                # Validate request
                valid, error_msg = validate_request(request)
                if not valid:
                    response = {"success": False, "error": error_msg}
                    sys.stdout.write(json.dumps(response) + "\n")
                    sys.stdout.flush()
                    continue
                
                # Process command
                response = process_command(connection, request)
                sys.stdout.write(json.dumps(response) + "\n")
                sys.stdout.flush()
                
            except Exception as e:
                # Don't crash on errors, log and continue
                response = {"success": False, "error": f"Internal error: {str(e)}"}
                sys.stdout.write(json.dumps(response) + "\n")
                sys.stdout.flush()
    
    finally:
        # Cleanup
        connection.close_all()


if __name__ == "__main__":
    main()
