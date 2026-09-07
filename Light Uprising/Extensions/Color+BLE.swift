//
//  Color+BLE.swift
//  Light Uprising
//
//  Color extensions for BLE RGB conversion
//

import SwiftUI

extension Color {
    /// Create Color from BLE service data bytes (HSV format)
    static func fromServiceData(_ data: Data) -> Color? {
        guard data.count >= 3 else { return nil }

        // Parse HSV values from bytes (0-255 range)
        let hue = Double(data[0]) / 255.0
        let saturation = Double(data[1]) / 255.0
        let value = Double(data[2]) / 255.0

        return Color(hue: hue, saturation: saturation, brightness: value)
    }
}
