//
//  Color+BLE.swift
//  Sparkle Friend
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
        } else if components.count >= 1 {
            // Grayscale color
            red = components[0]
            green = components[0]
            blue = components[0]
        } else {
            return (0, 0, 0)
        }

        return (
            red: UInt8(max(0, min(255, red * 255))),
            green: UInt8(max(0, min(255, green * 255))),
            blue: UInt8(max(0, min(255, blue * 255)))
        )
    }

    /// Create Color from BLE service data bytes
    static func fromServiceData(_ data: Data) -> Color? {
        guard data.count >= 3 else { return nil }
        return Color(red: data[0], green: data[1], blue: data[2])
    }
}
