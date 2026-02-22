//
//  PreviewGallery.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 20/10/25.
//

#if DEBUG
import SwiftUI

struct PreviewGallery_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.95), Color.black.opacity(0.7)],
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(["surroor", "goodvibes", "oneDirection"], id: \.self) { name in
                        Image(name)
                            .resizable()
                            .aspectRatio(1/1.2, contentMode: .fill)
                            .frame(width: 360, height: 360 * 1.2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.45), radius: 12, x: 6, y: 10)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    }
                }
                .padding()
            }
            .frame(height: 600)
        }
        .preferredColorScheme(.dark)
        .previewDevice("iPad Pro (11-inch)")
    }
}
#endif
