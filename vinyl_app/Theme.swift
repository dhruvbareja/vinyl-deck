//
//  Theme.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 19/10/25.
//

import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 12
    static let cardRadius: CGFloat = 14
    static let spineWidth: CGFloat = 16
    static let cardShadow = Color.black.opacity(0.38)
    static let backgroundTop = Color(red: 0.07, green: 0.05, blue: 0.12)
    static let backgroundBottom = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let softWhite = Color.white.opacity(0.92)
    static let subdued = Color.white.opacity(0.65)

    static func headlineFont() -> Font { .system(.title2, design: .rounded).weight(.semibold) }
    static func bodyFont() -> Font { .system(.body, design: .rounded) }
}
