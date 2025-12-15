//
//  Sparkle_FriendApp.swift
//  Sparkle Friend
//
//  BLE Light Controller App
//

import SwiftUI

@main
struct Sparkle_FriendApp: App {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
    }
}
