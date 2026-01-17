//
//  DeviceControlView.swift
//  Sparkle Friend
//
//  Device control interface for managing light settings
//

import SwiftUI

struct DeviceControlView: View {
    let device: BLEDevice
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColor: Color
    @State private var brightness: Double = 100
    @State private var isPowerOn: Bool = true
    @State private var selectedMode: Int = 0
    @State private var isConnecting: Bool = true

    init(device: BLEDevice) {
        self.device = device
        _selectedColor = State(initialValue: device.currentColor)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Connection status
                connectionStatusView

                // Large color preview
                colorPreviewView

                // Color picker
                colorControlSection

                // Mode selector
                modeControlSection

                // Brightness slider
                brightnessControlSection

                // Power toggle
                powerControlSection

                Spacer(minLength: 20)

                // Disconnect button
                disconnectButton
            }
            .padding()
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            connectToDevice()
        }
        .onDisappear {
            bluetoothManager.disconnect()
        }
    }

    // MARK: - View Components

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 8) {
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if bluetoothManager.connectedDevice?.id == device.id {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Disconnected")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var colorPreviewView: some View {
        VStack(spacing: 15) {
            ColorIndicatorView(color: selectedColor, size: 120)
                .shadow(radius: 10)

            Text("Current Color")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var colorControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.headline)

            ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: selectedColor) { oldValue, newValue in
                    sendColorUpdate(newValue)
                }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var modeControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mode")
                .font(.headline)

            if let error = bluetoothManager.modeListError {
                // Error state
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            } else if bluetoothManager.availableModes.isEmpty {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading modes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                // Loaded state with dynamic modes
                Picker("Mode", selection: $selectedMode) {
                    ForEach(bluetoothManager.availableModes) { mode in
                        Text(mode.name).tag(Int(mode.index))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMode) { oldValue, newValue in
                    sendModeUpdate(UInt8(newValue))
                }

                // Current mode display with name lookup
                if let currentMode = bluetoothManager.currentMode {
                    let modeName = bluetoothManager.availableModes
                        .first(where: { $0.index == currentMode })?
                        .name ?? "Mode \(currentMode)"

                    Text("Device mode: \(modeName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var brightnessControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Brightness")
                    .font(.headline)
                Spacer()
                Text("\(Int(brightness))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Slider(value: $brightness, in: 0...100, step: 1)
                .onChange(of: brightness) { oldValue, newValue in
                    sendBrightnessUpdate(UInt8(newValue * 2.55))
                }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var powerControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isPowerOn) {
                HStack {
                    Image(systemName: isPowerOn ? "power.circle.fill" : "power.circle")
                        .font(.title2)
                        .foregroundColor(isPowerOn ? .green : .gray)
                    Text("Power")
                        .font(.headline)
                }
            }
            .onChange(of: isPowerOn) { oldValue, newValue in
                sendPowerUpdate(newValue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var disconnectButton: some View {
        Button(action: {
            bluetoothManager.disconnect()
            dismiss()
        }) {
            Label("Disconnect", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
        }
    }

    // MARK: - Actions

    private func connectToDevice() {
        bluetoothManager.connect(to: device)

        // Wait a moment for connection to establish
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isConnecting = false

            // Read initial mode from device
            if let mode = bluetoothManager.currentMode {
                selectedMode = Int(mode)
            }
        }
    }

    private func sendColorUpdate(_ color: Color) {
        guard bluetoothManager.connectedDevice?.id == device.id else { return }
        bluetoothManager.setColor(color, for: device)
    }

    private func sendModeUpdate(_ mode: UInt8) {
        guard bluetoothManager.connectedDevice?.id == device.id else { return }
        bluetoothManager.setMode(mode, for: device)
    }

    private func sendBrightnessUpdate(_ brightness: UInt8) {
        guard bluetoothManager.connectedDevice?.id == device.id else { return }
        bluetoothManager.setBrightness(brightness, for: device)
    }

    private func sendPowerUpdate(_ on: Bool) {
        guard bluetoothManager.connectedDevice?.id == device.id else { return }
        bluetoothManager.setPowerState(on, for: device)
    }
}
