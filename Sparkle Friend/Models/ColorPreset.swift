//
//  ColorPreset.swift
//  Sparkle Friend
//
//  Created by Claude Code
//

import Foundation
import SwiftUI

/// Represents a preset color available on a BLE device
struct ColorPreset: Identifiable, Equatable, Hashable {
    let index: UInt8      // Color index for BLE transmission
    let hue: UInt8        // Hue value (0-255)
    let saturation: UInt8 // Saturation value (0-255)
    let value: UInt8      // Value/Brightness (0-255)

    var id: UInt8 { index }

    /// Convert HSV values to SwiftUI Color for display
    var color: Color {
        // Convert 0-255 range to 0-1 range for SwiftUI
        let h = Double(hue) / 255.0
        let s = Double(saturation) / 255.0
        let v = Double(value) / 255.0

        return Color(hue: h, saturation: s, brightness: v)
    }
}
