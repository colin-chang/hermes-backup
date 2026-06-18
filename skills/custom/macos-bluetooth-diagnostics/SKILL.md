---
name: macos-bluetooth-diagnostics
description: |
  Diagnose and fix macOS Bluetooth peripheral issues — incorrect device icons in Battery widget,
  device type misidentification, missing battery status, and BLE GATT Appearance mismatches.
  Covers both system-level fixes and firmware-level root cause analysis.
version: 1.0.0
platforms: [macos]
metadata:
  hermes:
    tags: [macos, bluetooth, battery, diagnostics, troubleshooting]
    category: custom
    related_skills: [macos-computer-use]
---

# macOS Bluetooth Device Diagnostics

Diagnose why macOS misidentifies Bluetooth peripherals — wrong icons in Battery
widget, missing from battery list, or showing as the wrong device type.

## Quick diagnostic flow

```
system_profiler SPBluetoothDataType
```

Check `device_minorType` and `device_services` for the device in question.

### The two code paths (critical distinction)

| Component | Data source | Affected by |
|-----------|-----------|-------------|
| Bluetooth Settings list | `IOBluetoothDevice.deviceMinorType` | macOS pairing metadata |
| Battery widget icon | BLE GATT Appearance characteristic | **Keyboard firmware only** |

If Bluetooth Settings shows correct type but Battery widget shows wrong icon →
**this is a firmware issue, not fixable from macOS side.**

## Fix tier list

### Tier 1: System-level (try first)

1. Forget device from Bluetooth Settings
2. Re-pair via **System Settings → Keyboard → "Set Up Bluetooth Keyboard…"**
   (NOT via ordinary Bluetooth pairing — this writes `deviceCategory=Keyboard` metadata)
3. If that fails, clear Bluetooth caches:

```bash
sudo rm /Library/Preferences/com.apple.Bluetooth.plist
rm ~/Library/Preferences/ByHost/com.apple.Bluetooth.*.plist
# Then restart and re-pair via Set Up Bluetooth Keyboard
```

### Tier 2: Firmware-level (when Tier 1 fails)

Root cause: keyboard firmware broadcasts wrong BLE GATT Appearance value.
Expected for keyboards: `0x03C1` (Generic Keyboard). If the firmware reports
something else, macOS BatteryCenter maps it to a wrong icon.

Options:
- Check manufacturer firmware updates
- File a support ticket citing "BLE GATT Appearance should be 0x03C1"
- Build custom QMK firmware with corrected appearance (advanced)

### Tier 3: Workaround

Use third-party battery apps that read IOBluetooth device type (not GATT Appearance):
- **Magic Battery** (free, Mac App Store)
- **Stats** (open source, menu bar)
- **AirBuddy** (paid, most polished)

These apps show correct icons because they use `IOBluetoothDevice.deviceMinorType`,
which is accurate even when GATT Appearance is wrong.

## Key terminal commands

```bash
# Connected Bluetooth devices with Minor Type
system_profiler SPBluetoothDataType 2>/dev/null | grep -A 20 "Connected:"

# Detailed JSON (for parsing)
system_profiler SPBluetoothDataType -json

# Check IOBluetooth registry (classic Bluetooth — BLE devices may not appear)
ioreg -r -c IOBluetoothDevice -a -l

# Battery widget preferences (lightweight, device list is runtime)
cat ~/Library/Preferences/com.apple.BatteryCenter.BatteryWidget.plist

# Bluetooth module reset (Shift+Option click Bluetooth menu bar icon → Reset)
sudo pkill bluetoothd
```

## Reference cases

- `references/keychron-k3-max-battery-widget.md` — Keychron K3 Max showing mouse
  icon in Battery widget despite correct `device_minorType`. Full diagnostic log,
  failed fix attempts, and GATT Appearance root cause analysis.

## Pitfalls

- **`system_profiler` shows correct Minor Type ≠ Battery widget will show correct icon.**
  They use different APIs. This is the #1 misunderstanding.
- **"Set Up Bluetooth Keyboard" is NOT the same as normal Bluetooth pairing.**
  The keyboard setup assistant writes additional metadata that BatteryCenter reads.
- **Deleting Bluetooth plists won't fix GATT Appearance issues.**
  The firmware re-advertises the wrong value on every reconnect.
- **BLE devices may not appear in `ioreg -c IOBluetoothDevice`.**
  BLE peripherals are often registered under different IOKit service classes.
- **CoreBluetooth via PyObjC requires `pyobjc-framework-CoreBluetooth`**
  which may not be installed; prefer `system_profiler` for diagnostics.
