# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Light Uprising is an iOS application for discovering and controlling Bluetooth Low Energy (BLE) light devices. The app scans for BLE lights advertising with a specific service UUID, displays them with their current color, and provides a full control interface for changing color, mode, brightness, and power state.

## Build and Test Commands

### Building the Application
```bash
# Build for iOS Simulator
xcodebuild -project "Light Uprising.xcodeproj" -scheme "Light Uprising" -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for iOS Device (requires connected device)
xcodebuild -project "Light Uprising.xcodeproj" -scheme "Light Uprising" -destination 'platform=iOS,name=YOUR_DEVICE_NAME' build

# Clean build
xcodebuild -project "Light Uprising.xcodeproj" -scheme "Light Uprising" clean build
```

### Running Tests
```bash
# Run all tests on iOS Simulator
xcodebuild test -project "Light Uprising.xcodeproj" -scheme "Light Uprising" -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test target
xcodebuild test -project "Light Uprising.xcodeproj" -scheme "Light Uprising" -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Light_UprisingTests

# Run UI tests
xcodebuild test -project "Light Uprising.xcodeproj" -scheme "Light Uprising" -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:Light_UprisingUITests
```

## Architecture

### Core Components

**BluetoothManager** (`Managers/BluetoothManager.swift`)
- Central BLE management class conforming to `CBCentralManagerDelegate` and `CBPeripheralDelegate`
- Handles scanning for BLE devices with service data UUID `c742e32d`
- Parses 3-byte RGB color data from advertisement service data
- Manages device connections, service/characteristic discovery, and BLE operations
- Published properties: `discoveredDevices`, `bluetoothState`, `isScanning`, `connectedDevice`, `currentMode`, `connectionError`
- Uses `DispatchQueue.main.async` for all UI updates to ensure thread safety

**BLEDevice Model** (`Models/BLEDevice.swift`)
- Represents a discovered BLE light device
- Properties: `id` (peripheral UUID), `name`, `currentColor`, `rssi` (signal strength), `lastSeen`, `peripheral` reference
- Conforms to `Identifiable`, `Equatable`, and `Hashable` for SwiftUI integration
- Devices are deduplicated by peripheral identifier

**Color Extensions** (`Extensions/Color+BLE.swift`)
- `Color.fromServiceData(_:)` - Creates SwiftUI Color from 3-byte RGB data
- `color.toRGBBytes()` - Converts SwiftUI Color to RGB byte tuple for BLE transmission
- Handles color space conversions between SwiftUI and BLE format

### View Hierarchy

```
Light_UprisingApp
  └─ ContentView (NavigationStack)
       ├─ DeviceListView - Shows discovered devices
       │    └─ DeviceRowView - Individual device row with color indicator and RSSI
       └─ DeviceControlView - Full control interface (navigation destination)
            ├─ ColorIndicatorView - Large color preview
            ├─ ColorPicker - Change light color
            ├─ Mode Picker - Select lighting mode
            ├─ Brightness Slider - Adjust brightness (0-100%)
            └─ Power Toggle - Turn light on/off
```

**ContentView.swift**
- Main discovery screen with NavigationStack
- Displays list of discovered BLE devices sorted by signal strength
- Empty states for: scanning, Bluetooth off, unauthorized
- Pull-to-refresh to restart scanning
- Navigation to DeviceControlView on device selection

**DeviceControlView.swift**
- Connects to selected device on appear
- Reads current mode from characteristic `0a93a285`
- Provides controls for color, mode, brightness, and power
- Shows connection status and handles disconnection
- Auto-disconnects when view disappears

**DeviceRowView.swift** & **ColorIndicatorView.swift**
- Reusable UI components for device display
- Color indicator shows circular preview of current light color
- Device row includes name, color, and signal strength visualization

### BLE Protocol Details

**Service UUID**: `c742e32d`
- Devices must advertise with service data for this UUID
- Service data contains 3 bytes: [Red, Green, Blue] (0-255 each)
- Extracted from C code: `serviceDataPayload[0-2]` = RGB bytes from packed color

**Characteristics**:
- **Mode Characteristic**: `0a93a285` (read/write)
  - Single byte value representing light mode (0=Solid, 1=Fade, 2=Flash, etc.)
  - Read on connection to display current mode
  - Write to change mode
- **Brightness Characteristic**: `9d4f2b60` (read/write)
  - Single byte value, 0-255 (0 = off, 255 = full brightness)
  - Read on connection to position the brightness slider
  - Written on slider change, throttled to one write per 50ms with a trailing write of the final value
- **Color/Power**: Discovered dynamically after connection
  - App searches for writable characteristics
  - Writes appropriate data based on characteristic properties
  - Uses `.writeWithoutResponse` or `.withResponse` based on characteristic

**Device Discovery**:
- Scans continuously with `allowDuplicates: true` to track RSSI changes
- Filters advertisements to only show devices with service UUID `c742e32d`
- Updates device list in real-time as devices are discovered
- Removes stale devices (not seen for 30 seconds)
- Sorted by signal strength (RSSI) for better UX

### Thread Safety

The app uses `DispatchQueue.main.async` extensively in CoreBluetooth delegate methods to ensure all `@Published` property updates happen on the main thread. This is required because:
- CoreBluetooth delegates are called on background threads
- SwiftUI `@Published` properties must be updated on the main thread
- The project has strict concurrency features disabled for compatibility

## Project Configuration

- **Platform**: iOS only (iPhone and iPad)
- **Bundle ID**: net.dashblue.Light-Uprising
- **Swift Version**: 5.0
- **Deployment Target**: iOS 17.0
- **Development Team**: 73C2JK825V
- **Code Signing**: Automatic
- **Sandboxing**: App Sandbox enabled
- **Bluetooth Permission**: `NSBluetoothAlwaysUsageDescription` configured

## Important Notes

### BLE Scanning Limitations
- iOS restricts background BLE scanning - app must be in foreground
- Service UUID filter reduces power consumption
- Scanning automatically resumes when app returns to foreground

### Service UUID Format
- Currently using short format: `C742E32D`
- If devices don't appear, may need full UUID: `0000C742-E32D-1000-8000-00805F9B34FB`
- Test with actual hardware to confirm correct format

### Characteristic Discovery
- Not all characteristics are known upfront (only mode characteristic)
- App discovers all services and characteristics after connection
- Looks for writable characteristics for color/brightness/power control
- Check Xcode console logs for discovered characteristic UUIDs when connecting

### Testing Without Hardware
- Use BLE peripheral simulator apps on another iOS device
- Advertise with service UUID `c742e32d` and 3-byte RGB service data
- Implement characteristics for full testing of control features

### Common Issues
- **Devices not appearing**: Verify service UUID format matches hardware
- **Can't control device**: Check characteristic UUIDs in console logs
- **Bluetooth permission denied**: Check Info.plist has correct usage description
- **Build errors**: Ensure iOS 17.0+ SDK is available
