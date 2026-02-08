//
//  ContentView.swift
//  Light Uprising
//
//  BLE Device Discovery List
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedDevice: BLEDevice?

    var body: some View {
        NavigationStack {
            ZStack {
                if bluetoothManager.discoveredDevices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle("Light Uprising")
            .navigationDestination(item: $selectedDevice) { device in
                DeviceControlView(device: device)
            }
            .alert("Bluetooth Required", isPresented: .constant(bluetoothManager.bluetoothState == .poweredOff)) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please turn on Bluetooth to discover light devices.")
            }
        }
    }

    @ViewBuilder
    private var deviceListView: some View {
        List(bluetoothManager.discoveredDevices) { device in
            Button {
                selectedDevice = device
            } label: {
                DeviceRowView(device: device)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .refreshable {
            // Pull to refresh - restart scanning
            bluetoothManager.stopScanning()
            try? await Task.sleep(nanoseconds: 500_000_000)
            bluetoothManager.startScanning()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            if bluetoothManager.bluetoothState == .poweredOn {
                // Scanning state
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()

                Text("Scanning for lights...")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Make sure your lights are powered on")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if bluetoothManager.bluetoothState == .unauthorized {
                // Permission denied
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                    .padding()

                Text("Bluetooth Permission Required")
                    .font(.headline)

                Text("Please grant Bluetooth permission in Settings to discover light devices.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
            } else {
                // Bluetooth off or other state
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                    .padding()

                Text("Bluetooth Unavailable")
                    .font(.headline)

                Text("Please turn on Bluetooth to discover light devices.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothManager())
}
