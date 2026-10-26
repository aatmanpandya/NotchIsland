// Draws the app icon into Resources/Assets.xcassets/AppIcon.appiconset.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit
import SwiftUI

/// The island's silhouette, as in the app: flared top corners, rounded bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in r: CGRect) -> Path {
        let tr = topRadius, br = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr, y: r.minY + tr), control: CGPoint(x: r.minX + tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr + br, y: r.maxY), control: CGPoint(x: r.minX + tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - tr, y: r.maxY - br), control: CGPoint(x: r.maxX - tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - tr, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: an 824-point rounded square centered in 1024.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.38),
                                              Color(red: 0.86, green: 0.33, blue: 0.52),
                                              Color(red: 0.33, green: 0.24, blue: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.35), .clear],
                                             center: .init(x: 0.3, y: 0.15), startRadius: 0, endRadius: 520))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 3)
                }
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 14)

            // The island, hanging from the top edge like the notch.
            VStack(spacing: 0) {
                ZStack {
                    NotchShape(topRadius: 34, bottomRadius: 110)
                        .fill(.black)
                        .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.35),
                                                          Color(red: 0.98, green: 0.4, blue: 0.45)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 150, height: 150)
                            .shadow(color: Color(red: 1, green: 0.55, blue: 0.4).opacity(0.7), radius: 24)
                        Spacer()
                        HStack(alignment: .center, spacing: 18) {
                            ForEach([0.55, 1.0, 0.7, 0.85], id: \.self) { level in
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.4),
                                                                  Color(red: 0.98, green: 0.45, blue: 0.5)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: 26, height: 150 * level)
                            }
                        }
                    }
                    .padding(.horizontal, 34 + 62)
                    .padding(.top, 40)
                }
                .frame(width: 700, height: 300)
                Spacer()
            }
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render() throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("Couldn't render the icon") }
    let folder = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let master = NSBitmapImageRep(cgImage: image)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            let resized = NSImage(size: NSSize(width: pixels, height: pixels), flipped: false) { rect in
                master.draw(in: rect)
                return true
            }
            guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try png.write(to: folder.appendingPathComponent(name))
        }
    }
    try master.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "build/AppIcon-1024.png"))
}

try MainActor.assumeIsolated { try render() }
