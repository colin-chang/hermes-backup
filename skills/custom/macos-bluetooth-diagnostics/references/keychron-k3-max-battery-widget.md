# Keychron K3 Max — Battery Widget Mouse Icon Case

## Device profile

| Field | Value |
|-------|-------|
| Model | Keychron K3 Max |
| Vendor ID | 0x3434 |
| Product ID | 0x0A3E |
| Bluetooth | BLE (services: 0x400000) |
| Firmware (BLE module) | 3.0.5 |
| Main firmware (latest) | 1.1.1 (2025-04-15) |
| `system_profiler` Minor Type | Keyboard ✅ |
| Battery widget icon | Mouse ❌ |

## Symptom

macOS Battery widget renders the keyboard with a mouse icon, despite
Bluetooth Settings correctly listing it as Minor Type: Keyboard.

## Root cause

K3 Max BLE firmware advertises a GATT Appearance value that macOS
BatteryCenter maps to "mouse" instead of "keyboard" (expected: 0x03C1).

The `system_profiler` IOBluetooth layer may derive `device_minorType` from
the HID report descriptor or other heuristics, so it shows "Keyboard"
correctly — but BatteryCenter reads GATT Appearance directly.

## What was tried (all failed)

1. Forget + re-pair via normal Bluetooth settings
2. "Set Up Bluetooth Keyboard" assistant in System Settings → Keyboard
3. Bluetooth plist cache deletion + restart + re-pair
4. Bluetooth module reset (Shift+Option click menu bar icon)

All failed because the GATT Appearance is re-read from firmware on every
reconnect, overriding any macOS-side metadata.

## Firmware changelog review

K3 Max latest firmware (1.1.1, April 2025) changelog mentions only:
- Fixed key double press (snap action debounce)
- Added Per-key RGB, Mixed RGB, LKP, sleep timer, etc.

No mention of GATT Appearance or battery icon fixes.

## Resolution path

1. **Immediate workaround**: Use Magic Battery (free, Mac App Store) or Stats
   (open source) — both read IOBluetooth device type correctly.
2. **Long-term fix**: Keychron must update firmware to set GATT Appearance to
   0x03C1. File a support ticket.
3. **DIY fix**: Build custom QMK firmware from `wireless_playground` branch,
   patch the BLE advertising appearance value, flash via Launcher.

## Diagnostic commands used

```bash
# Confirm Minor Type is correct
system_profiler SPBluetoothDataType | grep -A 5 "Keychron K3 Max"
# Output: device_minorType: Keyboard, device_services: 0x400000 < BLE >

# Battery widget plist (device list is runtime, not stored here)
cat ~/Library/Preferences/com.apple.BatteryCenter.BatteryWidget.plist
# Output: only localizedLargestString, no per-device config

# System Bluetooth prefs (also no per-device type override)
sudo defaults read /Library/Preferences/com.apple.Bluetooth
```
