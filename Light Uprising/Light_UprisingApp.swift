//
//  Light_UprisingApp.swift
//  Light Uprising
//
//  BLE Light Controller App
//

import SwiftUI

@main
struct Light_UprisingApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
    }
}
