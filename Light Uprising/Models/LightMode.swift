//
//  LightMode.swift
//  Light Uprising
//
//  Created by Claude Code
//

import Foundation

/// Represents a lighting mode available on a BLE device
struct LightMode: Identifiable, Equatable, Hashable {
    let index: UInt8      // Mode index for BLE transmission
    let name: String      // Display name

    var id: UInt8 { index }
}
