// Renders the app icon set from the project's tray icon design
// (claude_usage/icons/claude-tray.svg): an amber rounded square with a
// white "C" arc, laid out on Apple's macOS icon grid.
//
//   xcrun swift macos/tools/make_icon.swift macos/ClaudeUsage/App/Assets.xcassets/AppIcon.appiconset
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        // macOS grid: an 824pt body centred on a 1024pt canvas.
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.96, green: 0.62, blue: 0.04),   // #F59E0B
                             Color(red: 0.71, green: 0.33, blue: 0.04)],  // #B45309
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
            // The SVG's arc leaves a ~79° gap on the right.
            Circle()
                .trim(from: 0.11, to: 0.89)
                .stroke(.white, style: StrokeStyle(lineWidth: 84, lineCap: .round))
                .frame(width: 380, height: 380)
                .offset(x: -18)
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let master = MainActor.assumeIsolated { () -> NSBitmapImageRep in
    let r = ImageRenderer(content: Icon())
    r.scale = 1
    return NSBitmapImageRep(cgImage: r.cgImage!)
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        ctx.imageInterpolation = .high
        NSGraphicsContext.current = ctx
        master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!
            .write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)",
                       "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(out.path)")
