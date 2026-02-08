//
//  Color+BLE.swift
//  Light Uprising
//
//  Color extensions for BLE RGB conversion
//

import SwiftUI

extension Color {
    /// Create a Color from RGB bytes (0-255)
    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.init(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }

    /// Convert Color to RGB bytes for BLE transmission
    func toRGBBytes() -> (red: UInt8, green: UInt8, blue: UInt8) {
        // Get the RGB components from the color
        guard let components = UIColor(self).cgColor.components else {
            return (0, 0, 0)
        }

        // Handle grayscale colors (1-2 components) and RGB colors (3-4 components)
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        if components.count >= 3 {
            red = components[0]
            green = components[1]
            blue = components[2]
        } else {
            return (0, 0, 0)
        }

        return (
            red: UInt8(max(0, min(255, red * 255))),
            green: UInt8(max(0, min(255, green * 255))),
            blue: UInt8(max(0, min(255, blue * 255)))
        )
    }

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
