//
//  ImageHelpers.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 22/10/25.
//
/*
 import UIKit
 import SwiftUI
 import CoreGraphics
 
 final class ImageCache {
 static let shared = ImageCache()
 private init() {}
 
 private let cache = NSCache<NSString, UIImage>()
 
 func image(forKey key: String) -> UIImage? { cache.object(forKey: key as NSString) }
 func setImage(_ img: UIImage, forKey key: String) { cache.setObject(img, forKey: key as NSString) }
 }
 
 // Average color helper (fast, downscaled)
 extension UIImage {
 /// Returns a reasonably accurate average color by sampling a small downscaled context.
 func averageColor(downscaleTo size: CGSize = CGSize(width: 16, height: 16)) -> UIColor? {
 guard let cg = self.cgImage else { return nil }
 
 // draw a tiny scaled version
 let format = UIGraphicsImageRendererFormat()
 format.scale = 1
 let renderer = UIGraphicsImageRenderer(size: size, format: format)
 
 let img = renderer.image { ctx in
 ctx.cgContext.interpolationQuality = .medium
 ctx.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
 }
 
 guard let data = img.cgImage?.dataProvider?.data else { return nil }
 let ptr = CFDataGetBytePtr(data)
 let bytesPerPixel = 4
 var rTotal = 0, gTotal = 0, bTotal = 0, aTotal = 0
 let pixelCount = Int(size.width * size.height)
 
 for i in 0..<pixelCount {
 let offset = i * bytesPerPixel
 let r = Int(ptr?[offset] ?? 0)
 let g = Int(ptr?[offset + 1] ?? 0)
 let b = Int(ptr?[offset + 2] ?? 0)
 let a = Int(ptr?[offset + 3] ?? 0)
 rTotal += r; gTotal += g; bTotal += b; aTotal += a
 }
 
 if pixelCount == 0 { return nil }
 return UIColor(
 red: CGFloat(rTotal) / CGFloat(255 * pixelCount),
 green: CGFloat(gTotal) / CGFloat(255 * pixelCount),
 blue: CGFloat(bTotal) / CGFloat(255 * pixelCount),
 alpha: CGFloat(aTotal) / CGFloat(255 * pixelCount)
 )
 }
 }
 
 extension Color {
 init(uiColor: UIColor?) {
 if let u = uiColor { self = Color(u) } else { self = Color.clear }
 }
 }
 
*/
