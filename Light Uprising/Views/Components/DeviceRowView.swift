//
//  DeviceRowView.swift
//  Light Uprising
//
//  Device list row component showing name, color, and signal strength
//

import SwiftUI

struct DeviceRowView: View {
    let device: BLEDevice

    var body: some View {
        HStack(spacing: 15) {
            // Color indicator
            ColorIndicatorView(color: device.currentColor, size: 50)

            // Device info
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    // Signal strength indicator
                    signalStrengthView
                    Text("RSSI: \(device.rssi) dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Chevron for navigation
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var signalStrengthView: some View {
        let signalLevel = getSignalLevel(rssi: device.rssi)

        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Rectangle()
                    .fill(index < signalLevel ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + index * 3))
            }
        }
    }

    private func getSignalLevel(rssi: Int) -> Int {
        // Convert RSSI to signal level (0-3)
        if rssi >= -50 {
            return 3  // Excellent
        } else if rssi >= -70 {
            return 2  // Good
        } else if rssi >= -90 {
            return 1  // Fair
        } else {
            return 0  // Poor
        }
    }
}
