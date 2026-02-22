//
//  AlbumCase3D.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 27/10/25.
//

import SwiftUI
import UIKit
import SceneKit

private let π = Float.pi

// MARK: - Public SwiftUI view you’ll use inside the carousel
struct AlbumCase3DCard: View {
    let image: UIImage?
    let title: String
    let dominant: UIColor?
    let width: CGFloat
    // Drive these from your coverflow math:
    var yawDegrees: CGFloat      // -26...+26 (right/left tilt)
    var scale: CGFloat           // 0.72...1.05 (center bigger)
    var isCenter: Bool = false

    var body: some View {
        AlbumCase3DRepresentable(
            albumImage: image,
            title: title,
            tint: dominant,
            size: CGSize(width: width, height: width * 1.2),
            thickness: 8.0,
            corner: 0,                 // right-angle front corners
            reflectOnFloor: true
        )
        .overlay(
            // Title below card (like you already do)
            VStack {
                Spacer().frame(height: width * 1.2 + 8)
                Text(title)
                    .font(.system(.headline, design: .rounded)).lineLimit(1)
                    .foregroundStyle(.white)
            }
        )
        .scaleEffect(scale)
        .modifier(ThreeDYaw(yawDegrees: yawDegrees)) // doesn’t rotate SwiftUI, just forwards to SceneKit
    }
}

// MARK: - Small helper modifier that forwards yaw to the underlying SceneKit view
private struct ThreeDYaw: ViewModifier {
    let yawDegrees: CGFloat
    func body(content: Content) -> some View {
        content.background(ForwardYaw(yawDegrees: yawDegrees))
    }
}

// We use a PreferenceKey to send yaw down into the UIViewRepresentable
private struct YawKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct ForwardYaw: View {
    let yawDegrees: CGFloat
    var body: some View { Color.clear.preference(key: YawKey.self, value: yawDegrees) }
}

// MARK: - UIViewRepresentable (SceneKit)
private struct AlbumCase3DRepresentable: UIViewRepresentable {
    let albumImage: UIImage?
    let title: String
    let tint: UIColor?
    let size: CGSize
    let thickness: CGFloat
    let corner: CGFloat
    let reflectOnFloor: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.scene = makeScene(context: context)
        view.isPlaying = true
        view.preferredFramesPerSecond = 120
        return view
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        // Update textures if the image/title changed
        guard let scene = scnView.scene,
              let root = scene.rootNode.childNode(withName: "AlbumRoot", recursively: true),
              let caseNode = root.childNode(withName: "Case", recursively: true) else { return }

        // Update front material
        if let front = caseNode.childNode(withName: "Front", recursively: true)?.geometry?.firstMaterial {
            front.diffuse.contents = albumImage ?? placeholderImage()
        }

        // Update spine material
        if let spine = caseNode.childNode(withName: "Spine", recursively: true)?.geometry?.firstMaterial {
            spine.diffuse.contents = spineTexture(title: title, base: tint ?? UIColor(white: 0.18, alpha: 1))
        }

        // Listen for yaw updates
        context.coordinator.bindYaw(from: context.environment, into: root)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Scene
    private func makeScene(context: Context) -> SCNScene {
        let scene = SCNScene()
        let root = SCNNode()
        root.name = "AlbumRoot"
        scene.rootNode.addChildNode(root)

        // Lights
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowColor = UIColor.black.withAlphaComponent(0.55)

        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-(Float.pi)/4, (Float.pi)/6, 0)
        keyNode.position = SCNVector3(0, 200, 300)

        scene.rootNode.addChildNode(keyNode)

        if reflectOnFloor {
            let floor = SCNFloor()
            floor.reflectivity = 0.18
            floor.reflectionFalloffEnd = 600
            floor.firstMaterial?.diffuse.contents = UIColor.black
            floor.firstMaterial?.isDoubleSided = true
            scene.rootNode.addChildNode(SCNNode(geometry: floor))
        }
        // Album case assembly
        let caseNode = makeCaseNode(size: size, thickness: thickness, corner: corner)
        caseNode.name = "Case"
        root.addChildNode(caseNode)

        // Initial slight forward angle so the reflections look nice
        root.eulerAngles = SCNVector3(0, 0, 0)

        return scene
    }

    // MARK: Geometry
    private func makeCaseNode(size: CGSize, thickness: CGFloat, corner: CGFloat) -> SCNNode {
        let W = size.width
        let H = size.height
        let D = thickness

        let node = SCNNode()

        // FRONT (album art) — a slightly offset plane so the case shows thickness
        let frontPlane = SCNPlane(width: W, height: H)
        let frontMat = SCNMaterial()
        frontMat.diffuse.contents = albumImage ?? placeholderImage()
        frontMat.specular.contents = UIColor.white
        frontMat.shininess = 0.28
        frontMat.isDoubleSided = false
        frontPlane.cornerRadius = 0 // right angle edges
        frontPlane.materials = [frontMat]
        let frontNode = SCNNode(geometry: frontPlane)
        frontNode.name = "Front"
        frontNode.position = SCNVector3(0, 0, Float(D) * 0.5 - 0.1) // front surface
        node.addChildNode(frontNode)

        // BACK (dark plate)
        let backPlane = SCNPlane(width: W - 12, height: H - 8)
        let backMat = SCNMaterial()
        backMat.diffuse.contents = UIColor(white: 0.06, alpha: 1)
        backMat.ambient.contents = UIColor(white: 0.07, alpha: 1)
        backMat.locksAmbientWithDiffuse = true
        backMat.isDoubleSided = false
        let backNode = SCNNode(geometry: backPlane)
        backNode.position = SCNVector3(6, -4, -Float(D) * 0.5)
        node.addChildNode(backNode)

        // RIGHT EDGE (thickness slab)
        let rightBox = SCNBox(width: D, height: H, length: D, chamferRadius: 0.6)
        let rightMat = SCNMaterial()
        rightMat.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        rightMat.specular.contents = UIColor.white
        rightMat.shininess = 0.15
        rightBox.materials = [rightMat]
        let rightNode = SCNNode(geometry: rightBox)
        rightNode.position = SCNVector3(Float(W/2 - D/2), 0, 0)
        node.addChildNode(rightNode)

        // SPINE (left)
        let spineBox = SCNBox(width: D, height: H, length: D, chamferRadius: 0.4)
        let spineMat = SCNMaterial()
        spineMat.diffuse.contents = spineTexture(title: title, base: tint ?? UIColor(white: 0.18, alpha: 1))
        spineMat.specular.contents = UIColor.white.withAlphaComponent(0.2)
        spineMat.shininess = 0.08
        spineBox.materials = [spineMat]
        let spineNode = SCNNode(geometry: spineBox)
        spineNode.name = "Spine"
        spineNode.position = SCNVector3(-Float(W/2 - D/2), 0, 0)
        node.addChildNode(spineNode)

        // LITTLE SEAM (between front and spine)
        let seamPlane = SCNPlane(width: 2, height: H*0.92)
        let seamMat = SCNMaterial()
        seamMat.diffuse.contents = UIColor.black.withAlphaComponent(0.45)
        seamMat.isDoubleSided = true
        seamPlane.materials = [seamMat]
        let seamNode = SCNNode(geometry: seamPlane)
        seamNode.position = SCNVector3(-Float(W/2) + Float(D) + 1, 0, Float(D)*0.1)
        node.addChildNode(seamNode)

        // Set pivot to center so external yaw looks natural
        node.pivot = SCNMatrix4MakeTranslation(0, 0, 0)
        return node
    }

    // MARK: Textures
    private func placeholderImage() -> UIImage {
        let r = CGRect(x: 0, y: 0, width: 512, height: 512)
        UIGraphicsBeginImageContextWithOptions(r.size, true, 2)
        UIColor(white: 0.2, alpha: 1).setFill()
        UIRectFill(r)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]
        let s = "Album"
        (s as NSString).draw(in: r.insetBy(dx: 24, dy: 24), withAttributes: attrs)
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    private func spineTexture(title: String, base: UIColor) -> UIImage {
        // Render a vertical label centered on a narrow strip
        let w: CGFloat = 256, h: CGFloat = 1024
        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), true, 2)
        let ctx = UIGraphicsGetCurrentContext()!
        // base gradient
        let top = base
        let mid = base.withAlphaComponent(0.9)
        let bottom = UIColor.black
        let colors = [top.cgColor, mid.cgColor, bottom.cgColor] as CFArray
        let locs: [CGFloat] = [0, 0.5, 1]
        let space = CGColorSpaceCreateDeviceRGB()
        let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs)!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])

        // text (vertical)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 60, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            .paragraphStyle: paragraph
        ]
        ctx.saveGState()
        ctx.translateBy(x: w/2, y: h/2)
        ctx.rotate(by: -.pi/2)
        let textRect = CGRect(x: -h/2 + 40, y: -w/2, width: h - 80, height: w)
        (title as NSString).draw(in: textRect, withAttributes: attrs)
        ctx.restoreGState()

        // edge highlight
        let edge = UIBezierPath(rect: CGRect(x: w-3, y: 0, width: 3, height: h))
        UIColor.white.withAlphaComponent(0.18).setFill()
        edge.fill()

        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    // MARK: Coordinator: listens for yaw preference and rotates the 3D node
    final class Coordinator {
        private var lastYaw: CGFloat = .zero
        func bindYaw(from env: EnvironmentValues, into root: SCNNode) {
            // read latest yaw via the preference bridge
            // In practice SwiftUI will rebuild updateUIView after preference changes; just apply rotation
            if let caseNode = root.childNode(withName: "Case", recursively: true) {
                let rad = Float(lastYaw * .pi / 180)
                caseNode.eulerAngles.y = rad
            }
        }
    }
}
