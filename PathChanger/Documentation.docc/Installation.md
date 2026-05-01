# Installation

How to install and configure PathChanger.

## Overview

PathChanger requires Python 3 with pymobiledevice3 installed. Follow these steps to get started.

## System Requirements

- macOS 14.0 (Sonoma) or later
- Python 3.9 or later
- 50 MB disk space

## Installing Dependencies

### Python & pymobiledevice3

Install pymobiledevice3 using pip:

```bash
pip3 install -U pymobiledevice3
```

For Apple Silicon Macs, you may need to use Homebrew's Python:

```bash
brew install python@3.11
pip3.11 install -U pymobiledevice3
```

### Verify Installation

Verify pymobiledevice3 is correctly installed:

```bash
python3 -m pymobiledevice3 version
```

## iOS Device Setup

### Enable Developer Mode

1. On your iOS device, go to **Settings > Privacy & Security**
2. Scroll down and tap **Developer Mode**
3. Enable the toggle and restart when prompted
4. After restart, confirm enabling Developer Mode

### Trust Computer

1. Connect your iOS device via USB
2. Tap **Trust** on the device when prompted
3. Enter your device passcode

## First Launch

1. Open PathChanger
2. Grant necessary permissions when prompted
3. The app will automatically detect connected devices
4. Select a device from the sidebar to begin

## Troubleshooting

### Device Not Detected

- Ensure Developer Mode is enabled
- Try unplugging and reconnecting USB cable
- Use a high-quality USB cable (data-capable)
- Trust the computer on your device

### Python Not Found

- Verify Python 3 is installed: `which python3`
- Check pymobiledevice3: `python3 -m pymobiledevice3 version`
- Add Homebrew to PATH if using Apple Silicon

### Tunnel Connection Failed

- For iOS 17.4+, the app requires administrator privileges
- Enter your macOS password when prompted
- Ensure no other tunneld process is running
