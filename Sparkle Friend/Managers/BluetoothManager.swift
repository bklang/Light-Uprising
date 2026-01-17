//
//  BluetoothManager.swift
//  Sparkle Friend
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

    // Private properties
    private var centralManager: CBCentralManager!
    private var deviceCache: [UUID: BLEDevice] = [:]
    private var characteristicCache: [CBUUID: CBCharacteristic] = [:]
    private var connectedPeripheral: CBPeripheral?

    // Service and characteristic UUIDs
    private let serviceUUID = CBUUID(string: "C742E32D")
    private let modeCharacteristicUUID = CBUUID(string: "0A93A285")
    private let modeListCharacteristicUUID = CBUUID(string: "7F8A3C91")

    // Stale device cleanup interval (30 seconds)
    private let staleDeviceInterval: TimeInterval = 30

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
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
        print("Started scanning for BLE devices")
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        print("Stopped scanning")
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

    func setBrightness(_ brightness: UInt8, for device: BLEDevice) {
        guard let peripheral = connectedPeripheral,
              peripheral.identifier == device.id,
              peripheral.state == .connected else {
            print("Device not connected")
            return
        }

        let data = Data([brightness])
        print("Setting brightness to: \(brightness)")

        // Look for a brightness characteristic
        if let brightnessChar = characteristicCache.values.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }) {
            let writeType: CBCharacteristicWriteType = brightnessChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: brightnessChar, type: writeType)
        }
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

        updateDiscoveredDevicesList()
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

        // Update or add device on main thread
        let deviceID = peripheral.identifier
        let rssiValue = RSSI.intValue
        DispatchQueue.main.async {
            if var existingDevice = self.deviceCache[deviceID] {
                // Update existing device
                existingDevice.rssi = rssiValue
                existingDevice.lastSeen = Date()
                existingDevice.currentColor = color
                self.deviceCache[deviceID] = existingDevice
            } else {
                // Add new device
                let newDevice = BLEDevice(peripheral: peripheral, color: color, rssi: rssiValue)
                self.deviceCache[deviceID] = newDevice
                if let data = serviceData[CBUUID(string: "C742E32D")], data.count >= 3 {
                    print("Discovered device: \(newDevice.name) with color R:\(data[0]) G:\(data[1]) B:\(data[2])")
                }
            }

            self.updateDiscoveredDevicesList()
            self.removeStaleDevices()
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
                if characteristic.uuid == CBUUID(string: "0A93A285") {
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
