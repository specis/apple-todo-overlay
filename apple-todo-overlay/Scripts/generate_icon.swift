#!/usr/bin/swift
// Generates the app icon PNGs and writes Contents.json into the AppIcon.appiconset.
// Usage: swift Scripts/generate_icon.swift <path-to-appiconset>
import CoreGraphics
import ImageIO
import Foundation

let iconsetPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "."

// Pixel sizes to generate
let variants: [(px: Int, file: String)] = [
    (16,   "icon_16.png"),
    (32,   "icon_32.png"),
    (64,   "icon_64.png"),
    (128,  "icon_128.png"),
    (256,  "icon_256.png"),
    (512,  "icon_512.png"),
    (1024, "icon_1024.png"),
]

// MARK: - Render

func makeIcon(px: Int) -> CGImage? {
    let s = CGFloat(px)

    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Background — dark navy, iOS-style rounded corners
    let radius = s * 0.225
    ctx.setFillColor(CGColor(red: 0.059, green: 0.067, blue: 0.094, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    // Layout
    let margin    = s * 0.165
    let circleD   = s * 0.115
    let lineStart = margin + circleD + s * 0.042
    let lineRight = s - margin
    let rowY: [CGFloat]      = [s * 0.645, s * 0.500, s * 0.355]
    let rowLen: [CGFloat]    = [0.60, 0.88, 0.74]   // fraction of available line width
    let lw = max(1.5, s * 0.038)

    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
    let green = CGColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1)  // #30D158

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    for (i, cy) in rowY.enumerated() {
        let cx = margin + circleD / 2
        let r  = CGRect(x: cx - circleD/2, y: cy - circleD/2, width: circleD, height: circleD)

        if i == 0 {
            // Filled green circle
            ctx.setFillColor(green)
            ctx.fillEllipse(in: r)

            // White checkmark ✓
            let ch = circleD * 0.27
            ctx.setStrokeColor(CGColor.white)
            ctx.setLineWidth(lw * 0.70)
            ctx.move   (to: CGPoint(x: cx - ch * 0.90, y: cy + ch * 0.10))
            ctx.addLine(to: CGPoint(x: cx - ch * 0.15, y: cy - ch * 0.55))
            ctx.addLine(to: CGPoint(x: cx + ch * 0.85, y: cy + ch * 0.65))
            ctx.strokePath()
        } else {
            // White circle outline
            ctx.setStrokeColor(white)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: r)
        }

        // Horizontal line
        ctx.setStrokeColor(white)
        ctx.setLineWidth(lw)
        ctx.move   (to: CGPoint(x: lineStart, y: cy))
        ctx.addLine(to: CGPoint(x: lineStart + (lineRight - lineStart) * rowLen[i], y: cy))
        ctx.strokePath()
    }

    return ctx.makeImage()
}

// MARK: - Save

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        print("  ✗ \(path)"); return
    }
    CGImageDestinationAddImage(dest, image, nil)
    print(CGImageDestinationFinalize(dest) ? "  ✓ \(path)" : "  ✗ \(path)")
}

// MARK: - Run

print("Generating icon...")
for v in variants {
    if let img = makeIcon(px: v.px) {
        savePNG(img, to: "\(iconsetPath)/\(v.file)")
    }
}

// Write Contents.json
let json = """
{
  "images" : [
    { "filename": "icon_16.png",   "idiom": "mac", "scale": "1x", "size": "16x16"   },
    { "filename": "icon_32.png",   "idiom": "mac", "scale": "2x", "size": "16x16"   },
    { "filename": "icon_32.png",   "idiom": "mac", "scale": "1x", "size": "32x32"   },
    { "filename": "icon_64.png",   "idiom": "mac", "scale": "2x", "size": "32x32"   },
    { "filename": "icon_128.png",  "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_256.png",  "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256.png",  "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_512.png",  "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512.png",  "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_1024.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info" : { "author": "xcode", "version": 1 }
}
"""
try! json.write(toFile: "\(iconsetPath)/Contents.json", atomically: true, encoding: .utf8)
print("  ✓ Contents.json")
print("Done.")
