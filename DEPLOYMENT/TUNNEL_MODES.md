# Tunnel Mode Selection Guide

PathChanger supports four tunnel modes for connecting to iOS devices. This guide helps you choose the right mode for your use case.

## Quick Reference

| Mode | Connection | Best For | Speed | Reliability |
|------|------------|----------|-------|-------------|
| **Auto** | Automatic | General use | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **USB** | Lightning/USB-C | Development | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **WiFi** | Same network | Untethered use | ⭐⭐ | ⭐⭐⭐ |
| **Daemon** | Background service | Always-on | ⭐⭐⭐ | ⭐⭐⭐⭐ |

## Mode Details

### Auto Mode (Recommended)

**Description:** Automatically selects the best available mode based on device connectivity.

**Requirements:**
- No additional setup required
- Works with USB or WiFi connections

**When to use:**
- First-time users
- General testing and development
- When you want "just works" behavior

**Behavior:**
1. Checks for USB-connected devices first
2. Falls back to WiFi discovery if no USB device
3. Automatically reconnects on connection loss

---

### USB Mode

**Description:** Direct connection via Lightning or USB-C cable.

**Requirements:**
- iOS device connected via cable
- Device trusted on Mac
- Developer Mode enabled on iOS 16+

**When to use:**
- Maximum reliability needed
- Low-latency simulation (gaming, AR)
- Development and testing
- When WiFi is unstable or unavailable

**Pros:**
- Fastest and most reliable
- Works offline
- No network configuration

**Cons:**
- Device must be tethered
- Cable limits mobility

**Troubleshooting:**
- Verify cable is working (try charging)
- Check `System Settings > Privacy & Security > Developer Mode`
- Re-trust the Mac if prompted

---

### WiFi Mode

**Description:** Wireless connection over local network.

**Requirements:**
- iOS device and Mac on same network
- WiFi must allow device discovery (no AP isolation)
- Device previously paired via USB

**When to use:**
- Untethered device testing
- Multiple device testing
- Physical mobility needed

**Pros:**
- No cable required
- Free movement with device
- Multiple devices simultaneously

**Cons:**
- Higher latency than USB
- Network-dependent reliability
- Initial USB pairing required

**Troubleshooting:**
- Verify both devices on same network
- Check router for AP isolation settings
- Pair device via USB first, then disconnect
- Try `killall usbmuxd` and retry

---

### Daemon Mode

**Description:** Runs tunneld as a background service for persistent connections.

**Requirements:**
- Administrator privileges (first launch)
- pymobiledevice3 installed

**When to use:**
- Long-running simulations
- Server/automation scenarios
- Multiple app sessions
- Background location simulation

**Pros:**
- Survives app restarts
- Shared between multiple apps
- Persistent connection

**Cons:**
- Requires admin privileges to start
- Uses system resources continuously
- Must be manually stopped

**Troubleshooting:**
- Check `ps aux | grep tunneld` for running process
- View logs at `~/Library/Logs/PathChanger/tunnel.log`
- Kill orphan processes: `pkill -f pymobiledevice3`

---

## Comparison Matrix

### By Reliability

| Scenario | Recommended Mode |
|----------|-----------------|
| Demo/presentation | USB |
| QA testing | Auto |
| Long-duration test | Daemon |
| Multi-device test | WiFi |

### By Latency

| Requirement | Mode | Expected Latency |
|-------------|------|------------------|
| Real-time | USB | <50ms |
| Interactive | Auto/Daemon | 50-150ms |
| Background | WiFi | 100-300ms |

### By Setup Complexity

| Mode | Setup Steps |
|------|-------------|
| USB | 1. Connect cable |
| Auto | 0. Just launch |
| WiFi | 1. USB pair → 2. Disconnect → 3. Same network |
| Daemon | 1. Launch → 2. Enter admin password |

---

## Common Issues

### "No devices found"

1. **USB Mode:**
   - Check cable connection
   - Trust Mac on device (unlock device)
   - Enable Developer Mode in Settings

2. **WiFi Mode:**
   - Verify same network
   - USB-pair device first
   - Check firewall settings

3. **Daemon Mode:**
   - Ensure daemon started successfully
   - Check for port conflicts on 49151

### "Tunnel connection failed"

- Restart PathChanger
- Kill existing tunnel processes
- Update pymobiledevice3: `pip3 install -U pymobiledevice3`

### "Permission denied"

- Daemon mode requires admin privileges
- Check macOS Privacy settings for Terminal/app

---

## Performance Tips

1. **For lowest latency:** Use USB mode
2. **For battery efficiency:** Daemon mode (one process for all)
3. **For debugging:** USB mode with Console.app monitoring
4. **For testing:** Auto mode with multiple retry enabled

---

## Technical Details

### Port Usage

| Port | Purpose |
|------|---------|
| 49151 | Tunneld HTTP API |
| 49152+ | Individual device tunnels |
| 62078 | Lockdown service |

### Process Names

- `pymobiledevice3` - Main tunnel process
- `tunneld` - Daemon mode service
- `usbmuxd` - USB multiplexer (system)

---

## See Also

- [Troubleshooting Guide](../README.md#troubleshooting)
