//
//  BLEDevice.swift
//  Sparkle Friend
//
//  BLE device model representing a discovered light device
//

import Foundation
import SwiftUI
import CoreBluetooth

struct BLEDevice: Identifiable, Equatable, Hashable {
    let id: UUID              // peripheral.identifier
    var name: String          // device name from advertisement or peripheral
    var currentColor: Color   // from service data RGB
    var rssi: Int             // signal strength
    var lastSeen: Date        // for stale device cleanup
    let peripheral: CBPeripheral

    init(peripheral: CBPeripheral, name: String, color: Color, rssi: Int) {
        self.id = peripheral.identifier
        self.name = name
        self.currentColor = color
        self.rssi = rssi
        self.lastSeen = Date()
        self.peripheral = peripheral
    }

    // Equatable conformance - compare by UUID only
    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        lhs.id == rhs.id
    }

    // Hashable conformance - hash by UUID only
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
