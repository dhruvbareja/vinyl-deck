//
//  CardStyleModifier.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 19/10/25.
import SwiftUI



struct CardStyleModifier: ViewModifier {
    var radius: CGFloat = AppTheme.cardRadius
    var shadowRadius: CGFloat = 12
    var lifted: Bool = false

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.8)
                    .blendMode(.overlay)
            )
            .shadow(color: AppTheme.cardShadow, radius: shadowRadius, x: lifted ? 8 : 4, y: lifted ? 12 : 6)
    }
}

extension View {
    func cardStyle(radius: CGFloat = AppTheme.cardRadius, lifted: Bool = false) -> some View {
        modifier(CardStyleModifier(radius: radius, lifted: lifted))
    }
}
