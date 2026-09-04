//
//  BluetoothManager.swift
//  Light Uprising
//
//  Manages BLE scanning, connection, and device control
//

import Foundation
@preconcurrency import CoreBluetooth
import SwiftUI

class BluetoothManager: NSObject, ObservableObject {
    // Published state
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var isScanning: Bool = false
    @Published var connectedDevice: BLEDevice?
    @Published var currentMode: UInt8?
    @Published var connectionError: String?
    @Published var availableModes: [LightMode] = []
    @Published var modeListError: String?
    @Published var availableColors: [ColorPreset] = []
    @Published var colorListError: String?
    @Published var currentColorPresetIndex: UInt8?
    @Published var currentBrightness: UInt8?
    @Published var brightnessError: String?

    // Private properties
    private var centralManager: CBCentralManager!
    private var deviceCache: [UUID: BLEDevice] = [:]
    private var characteristicCache: [CBUUID: CBCharacteristic] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var updateTimer: Timer?
    private var cacheNeedsUpdate = false
    private var pendingBrightness: UInt8?
    private var brightnessWriteTimer: Timer?
    private var lastBrightnessWriteAt: Date?

    // Service and characteristic UUIDs
    private let serviceUUID = CBUUID(string: "C742E32D")
    private let modeCharacteristicUUID = CBUUID(string: "0A93A285")
    private let modeListCharacteristicUUID = CBUUID(string: "7F8A3C91")
    private let colorListCharacteristicUUID = CBUUID(string: "4B2E9F17")
    private let colorPresetCharacteristicUUID = CBUUID(string: "15EC18FE")
    private let brightnessCharacteristicUUID = CBUUID(string: "9D4F2B60")

    // Update intervals
    private let staleDeviceInterval: TimeInterval = 30
    private let uiUpdateInterval: TimeInterval = 1.0 // Update UI every 1 second
    private let brightnessWriteInterval: TimeInterval = 0.05 // Throttle slider writes

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    deinit {
        stopUpdateTimer()
        brightnessWriteTimer?.invalidate()
    }

    // MARK: - Scanning

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Cannot start scanning - Bluetooth not powered on")
            return
        }

        // Scan for devices with our service UUID in their service data
        centralManager.scanForPeripherals(
            withServices: nil, // Scan for all devices to see service data
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true

        // Start timer to periodically update the UI
        startUpdateTimer()

        print("Started scanning for BLE devices")
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false

        // Stop the update timer
        stopUpdateTimer()

        print("Stopped scanning")
    }

    private func startUpdateTimer() {
        // Invalidate existing timer if any
        updateTimer?.invalidate()

        // Create a new timer that fires every uiUpdateInterval seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: uiUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateDeviceListIfNeeded()
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateDeviceListIfNeeded() {
        guard cacheNeedsUpdate else { return }
        cacheNeedsUpdate = false
        updateDiscoveredDevicesList()
        removeStaleDevices()
    }

    // MARK: - Connection Management

    func connect(to device: BLEDevice) {
        print("Connecting to device: \(device.name)")
        connectedPeripheral = device.peripheral
        device.peripheral.delegate = self
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        print("Disconnecting from device")
        centralManager.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        connectedDevice = nil
        currentMode = nil
        availableModes = []
        modeListError = nil
        availableColors = []
        colorListError = nil
        currentColorPresetIndex = nil
        resetBrightnessState()
        characteristicCache.removeAll()
    }

    // MARK: - Mode List Parsing

    private func parseModeList(from data: Data) -> [LightMode] {
        // Convert to UTF-8 string
        guard let modeString = String(data: data, encoding: .utf8) else {
            print("ERROR: Failed to decode mode list as UTF-8")
            return []
        }

        print("Mode list string: \(modeString)")

        // Parse "index:name,index:name" format
        let entries = modeString.split(separator: ",")
        var modes: [LightMode] = []

        for entry in entries {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let index = UInt8(parts[0].trimmingCharacters(in: .whitespaces)),
                  !parts[1].isEmpty else {
                print("WARNING: Skipping malformed entry: \(entry)")
                continue
            }

            let name = parts[1].trimmingCharacters(in: .whitespaces)
            modes.append(LightMode(index: index, name: name))
        }

        modes.sort { $0.index < $1.index }
        print("Parsed \(modes.count) modes")
        return modes
    }

    // MARK: - Color List Parsing

    private func parseColorList(from data: Data) -> [ColorPreset] {
        // Convert to UTF-8 string
        guard let colorString = String(data: data, encoding: .utf8) else {
            print("ERROR: Failed to decode color list as UTF-8")
            return []
        }

        print("Color list string: \(colorString)")

        // Parse "index:HHSSVV,index:HHSSVV" format
        // where HH=hue, SS=saturation, VV=value (all in hex)
        let entries = colorString.split(separator: ",")
        var colors: [ColorPreset] = []

        for entry in entries {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let index = UInt8(parts[0].trimmingCharacters(in: .whitespaces)) else {
                print("WARNING: Skipping malformed entry (bad index): \(entry)")
                continue
            }

            let hsvHex = parts[1].trimmingCharacters(in: .whitespaces)

            // Expect exactly 6 hex characters (HH SS VV)
            guard hsvHex.count == 6,
                  let hue = UInt8(hsvHex.prefix(2), radix: 16),
                  let saturation = UInt8(hsvHex.dropFirst(2).prefix(2), radix: 16),
                  let value = UInt8(hsvHex.suffix(2), radix: 16) else {
                print("WARNING: Skipping malformed entry (bad HSV hex): \(entry)")
                continue
            }

            colors.append(ColorPreset(index: index, hue: hue, saturation: saturation, value: value))
            print("  Parsed color preset \(index): H=\(hue) S=\(saturation) V=\(value)")
        }

        colors.sort { $0.index < $1.index }
        print("Parsed \(colors.count) colors")
        return colors
    }

    // MARK: - Device Control

    func setColor(_ color: Color, for device: BLEDevice) {
        guard let peripheral = connectedPeripheral,
              peripheral.identifier == device.id,
              peripheral.state == .connected else {
            print("Device not connected")
            return
        }

        let rgb = color.toRGBBytes()
        let data = Data([rgb.red, rgb.green, rgb.blue])

        // Try to find a color characteristic (we'll discover this dynamically)
        // For now, we'll need to discover characteristics first
        print("Setting color to R:\(rgb.red) G:\(rgb.green) B:\(rgb.blue)")

        // Look for a writable characteristic to send color data
        if let colorCharacteristic = characteristicCache.values.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }) {
            let writeType: CBCharacteristicWriteType = colorCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: colorCharacteristic, type: writeType)
        }
    }

    func setMode(_ mode: UInt8, for device: BLEDevice) {
        guard let peripheral = connectedPeripheral,
              peripheral.identifier == device.id,
              peripheral.state == .connected,
              let modeCharacteristic = characteristicCache[modeCharacteristicUUID] else {
            print("Cannot set mode - device not connected or characteristic not found")
            return
        }

        let data = Data([mode])
        let writeType: CBCharacteristicWriteType = modeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: modeCharacteristic, type: writeType)
        print("Set mode to: \(mode)")
    }

    func setColorPreset(_ presetIndex: UInt8, for device: BLEDevice) {
        guard let peripheral = connectedPeripheral,
              peripheral.identifier == device.id,
              peripheral.state == .connected,
              let colorPresetCharacteristic = characteristicCache[colorPresetCharacteristicUUID] else {
            print("Cannot set color preset - device not connected or characteristic not found")
            return
        }

        // Optimistically update UI immediately
        DispatchQueue.main.async {
            self.currentColorPresetIndex = presetIndex
        }

        let data = Data([presetIndex])
        let writeType: CBCharacteristicWriteType = colorPresetCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: colorPresetCharacteristic, type: writeType)
        print("Set color preset to: \(presetIndex)")
    }

    func setBrightness(_ brightness: UInt8, for device: BLEDevice) {
        guard let peripheral = connectedPeripheral,
              peripheral.identifier == device.id,
              peripheral.state == .connected,
              characteristicCache[brightnessCharacteristicUUID] != nil else {
            print("Cannot set brightness - device not connected or characteristic not found")
            return
        }

        // Optimistically update UI immediately
        DispatchQueue.main.async {
            self.currentBrightness = brightness
        }

        // Throttle writes so a slider drag doesn't flood the BLE write queue,
        // but always write the value the user finally landed on.
        let now = Date()
        if let lastWrite = lastBrightnessWriteAt {
            let elapsed = now.timeIntervalSince(lastWrite)
            if elapsed < brightnessWriteInterval {
                pendingBrightness = brightness
                scheduleBrightnessFlush(after: brightnessWriteInterval - elapsed)
                return
            }
        }

        lastBrightnessWriteAt = now
        writeBrightnessNow(brightness)
    }

    private func scheduleBrightnessFlush(after delay: TimeInterval) {
        // An already-scheduled flush will pick up the newest pending value
        guard brightnessWriteTimer == nil else { return }

        brightnessWriteTimer = Timer.scheduledTimer(withTimeInterval: max(delay, 0), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.brightnessWriteTimer = nil

            guard let pending = self.pendingBrightness else { return }
            self.pendingBrightness = nil
            self.lastBrightnessWriteAt = Date()
            self.writeBrightnessNow(pending)
        }
    }

    private func writeBrightnessNow(_ brightness: UInt8) {
        // Re-check state: a trailing flush can fire after a disconnect
        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let brightnessCharacteristic = characteristicCache[brightnessCharacteristicUUID] else {
            print("Skipping brightness write - device no longer connected")
            return
        }

        let data = Data([brightness])
        let writeType: CBCharacteristicWriteType = brightnessCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: brightnessCharacteristic, type: writeType)
        print("Set brightness to: \(brightness)")
    }

    private func resetBrightnessState() {
        brightnessWriteTimer?.invalidate()
        brightnessWriteTimer = nil
        pendingBrightness = nil
        lastBrightnessWriteAt = nil
        currentBrightness = nil
        brightnessError = nil
    }

    func setPowerState(_ on: Bool, for device: BLEDevice) {
        guard let peripheral = connectedPeripheral,
              peripheral.identifier == device.id,
              peripheral.state == .connected else {
            print("Device not connected")
            return
        }

        let data = Data([on ? 1 : 0])
        print("Setting power state to: \(on ? "ON" : "OFF")")

        // Look for a power characteristic
        if let powerChar = characteristicCache.values.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }) {
            let writeType: CBCharacteristicWriteType = powerChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: powerChar, type: writeType)
        }
    }

    // MARK: - Device Cleanup

    private func removeStaleDevices() {
        let now = Date()
        let staleDeviceIDs = deviceCache.filter {
            now.timeIntervalSince($0.value.lastSeen) > staleDeviceInterval
        }.map { $0.key }

        for id in staleDeviceIDs {
            deviceCache.removeValue(forKey: id)
        }
    }

    private func updateDiscoveredDevicesList() {
        discoveredDevices = Array(deviceCache.values).sorted { $0.rssi > $1.rssi }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
        }

        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            startScanning()
        case .poweredOff:
            print("Bluetooth is powered off")
            stopScanning()
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .unsupported:
            print("Bluetooth is not supported on this device")
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any],
                       rssi RSSI: NSNumber) {

        // Filter: only show devices with our service data UUID
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let color = Color.fromServiceData(serviceData[CBUUID(string: "C742E32D")] ?? Data()) else {
            return
        }

        // Try to get device name from advertisement data, fallback to peripheral.name
        let deviceName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                      ?? peripheral.name
                      ?? "Unknown Device"

        // Update or add device on main thread
        let deviceID = peripheral.identifier
        let rssiValue = RSSI.intValue
        DispatchQueue.main.async {
            if var existingDevice = self.deviceCache[deviceID] {
                // Update existing device
                existingDevice.rssi = rssiValue
                existingDevice.lastSeen = Date()
                existingDevice.currentColor = color
                // Update name if we now have a better one (not "Unknown Device")
                if deviceName != "Unknown Device" && existingDevice.name == "Unknown Device" {
                    existingDevice.name = deviceName
                }
                self.deviceCache[deviceID] = existingDevice
            } else {
                // Add new device
                let newDevice = BLEDevice(peripheral: peripheral, name: deviceName, color: color, rssi: rssiValue)
                self.deviceCache[deviceID] = newDevice
                if let data = serviceData[CBUUID(string: "C742E32D")], data.count >= 3 {
                    print("Discovered device: \(newDevice.name) with color H:\(data[0]) S:\(data[1]) V:\(data[2])")
                }
            }

            // Mark that the cache has been updated
            self.cacheNeedsUpdate = true
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to device: \(peripheral.name ?? "Unknown")")

        // Find the device in our cache
        DispatchQueue.main.async {
            if let device = self.deviceCache[peripheral.identifier] {
                self.connectedDevice = device
                self.connectionError = nil
            }
        }

        // Discover services
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        let errorMsg = error?.localizedDescription ?? "Failed to connect"
        DispatchQueue.main.async {
            self.connectionError = errorMsg
            self.connectedPeripheral = nil
            self.connectedDevice = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from device: \(peripheral.name ?? "Unknown")")
        if let error = error {
            print("Disconnect error: \(error.localizedDescription)")
        }
        let errorMsg = error?.localizedDescription
        DispatchQueue.main.async {
            if let errorMsg = errorMsg {
                self.connectionError = errorMsg
            }
            self.connectedPeripheral = nil
            self.connectedDevice = nil
            self.currentMode = nil
            self.currentColorPresetIndex = nil
            self.resetBrightnessState()
            self.characteristicCache.removeAll()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        print("Discovered \(services.count) services")

        for service in services {
            print("Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }
        print("Discovered \(characteristics.count) characteristics for service \(service.uuid)")

        DispatchQueue.main.async {
            for characteristic in characteristics {
                print("  Characteristic: \(characteristic.uuid), properties: \(characteristic.properties)")

                // Cache all characteristics
                self.characteristicCache[characteristic.uuid] = characteristic

                // If this is the mode characteristic, read its value
                if characteristic.uuid == self.modeCharacteristicUUID {
                    peripheral.readValue(for: characteristic)
                }

                // If this is the mode list characteristic, read its value
                if characteristic.uuid == self.modeListCharacteristicUUID {
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    } else {
                        print("WARNING: Mode list characteristic not readable")
                        self.modeListError = "Mode list characteristic not readable"
                    }
                }

                // If this is the color list characteristic, read its value
                if characteristic.uuid == self.colorListCharacteristicUUID {
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    } else {
                        print("WARNING: Color list characteristic not readable")
                        self.colorListError = "Color list characteristic not readable"
                    }
                }

                // If this is the color preset characteristic, read its value
                if characteristic.uuid == self.colorPresetCharacteristicUUID {
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    }
                }

                // If this is the brightness characteristic, read its value
                if characteristic.uuid == self.brightnessCharacteristicUUID {
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    } else {
                        print("WARNING: Brightness characteristic not readable")
                        self.brightnessError = "Brightness characteristic not readable"
                    }
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("Error reading characteristic: \(error.localizedDescription)")
            return
        }

        // Handle mode characteristic read
        if characteristic.uuid == CBUUID(string: "0A93A285"),
           let data = characteristic.value,
           data.count >= 1 {
            let modeValue = data[0]
            DispatchQueue.main.async {
                self.currentMode = modeValue
            }
            print("Current mode: \(modeValue)")
        }

        // Handle mode list characteristic read
        if characteristic.uuid == modeListCharacteristicUUID,
           let data = characteristic.value {
            let modes = parseModeList(from: data)
            DispatchQueue.main.async {
                if modes.isEmpty {
                    self.modeListError = "No valid modes parsed from device"
                    self.availableModes = []
                } else {
                    self.availableModes = modes
                    self.modeListError = nil
                }
            }
        }

        // Handle color list characteristic read
        if characteristic.uuid == colorListCharacteristicUUID,
           let data = characteristic.value {
            let colors = parseColorList(from: data)
            DispatchQueue.main.async {
                if colors.isEmpty {
                    self.colorListError = "No valid color presets parsed from device"
                    self.availableColors = []
                } else {
                    self.availableColors = colors
                    self.colorListError = nil
                }
            }
        }

        // Handle color preset characteristic read
        if characteristic.uuid == colorPresetCharacteristicUUID,
           let data = characteristic.value,
           data.count >= 1 {
            let presetIndex = data[0]
            DispatchQueue.main.async {
                self.currentColorPresetIndex = presetIndex
            }
            print("Current color preset index: \(presetIndex)")
        }

        // Handle brightness characteristic read
        if characteristic.uuid == brightnessCharacteristicUUID,
           let data = characteristic.value,
           data.count >= 1 {
            let brightnessValue = data[0]
            DispatchQueue.main.async {
                self.currentBrightness = brightnessValue
                self.brightnessError = nil
            }
            print("Current brightness: \(brightnessValue)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("Error writing characteristic: \(error.localizedDescription)")
            let errorMsg = error.localizedDescription
            DispatchQueue.main.async {
                self.connectionError = errorMsg
            }
        } else {
            print("Successfully wrote to characteristic: \(characteristic.uuid)")
        }
    }
}
