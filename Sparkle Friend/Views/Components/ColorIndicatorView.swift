//
//  ColorIndicatorView.swift
//  Sparkle Friend
//
//  Displays a colored circle indicator for device color
//

import SwiftUI

struct ColorIndicatorView: View {
    let color: Color
    let size: CGFloat

    init(color: Color, size: CGFloat = 40) {
        self.color = color
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .shadow(radius: 2)
    }
}

#Preview {
    VStack(spacing: 20) {
        ColorIndicatorView(color: .red)
        ColorIndicatorView(color: .green)
        ColorIndicatorView(color: .blue)
        ColorIndicatorView(color: Color(red: 255, green: 128, blue: 64), size: 60)
    }
    .padding()
}
