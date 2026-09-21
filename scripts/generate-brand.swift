import AppKit
import Foundation

// Balanced hammock: one shared geometry definition for editable SVG and native raster exports.
enum Segment {
    case move(CGFloat, CGFloat), curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat), close
}
struct Shape {
    var segments: [Segment]
    var color: String
    var svg: String {
        segments.map {
            switch $0 {
            case let .move(x, y): return "M\(x),\(y)"
            case let .curve(a, b, c, d, e, f): return "C\(a),\(b) \(c),\(d) \(e),\(f)"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }
    var path: CGPath {
        let p = CGMutablePath()
        for segment in segments {
            switch segment {
            case let .move(x, y): p.move(to: CGPoint(x: x, y: y))
            case let .curve(a, b, c, d, e, f):
                p.addCurve(to: CGPoint(x: e, y: f), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
            case .close: p.closeSubpath()
            }
        }
        return p
    }
}
let fabric = [
    Shape(segments: [.move(36, 66), .curve(79, 118, 149, 170, 215, 153),
                     .curve(243, 130, 267, 98, 284, 66), .curve(276, 152, 251, 218, 164, 218),
                     .curve(91, 218, 54, 168, 36, 66), .close], color: "#42B38E"),
    Shape(segments: [.move(36, 66), .curve(79, 118, 149, 170, 215, 153),
                     .curve(177, 179, 147, 196, 111, 201), .curve(71, 175, 48, 118, 36, 66), .close], color: "#91D1B9"),
    Shape(segments: [.move(36, 66), .curve(63, 131, 108, 187, 162, 175),
                     .curve(136, 192, 111, 204, 93, 199), .curve(63, 180, 46, 128, 36, 66), .close], color: "#258E73"),
    Shape(segments: [.move(93, 199), .curve(116, 201, 140, 190, 162, 175),
                     .curve(180, 172, 198, 164, 215, 153), .curve(186, 181, 143, 209, 93, 199), .close], color: "#339E7C")
]
let circles: [(CGFloat, CGFloat, CGFloat, String)] = [(36, 66, 12, "#248F74"), (284, 66, 12, "#248F74"), (188, 124, 24, "#46B68F")]
func color(_ hex: String) -> CGColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((n >> 16) & 255) / 255,
                   green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
}
func mark(_ context: CGContext, monochrome: Bool = false) {
    for shape in monochrome ? Array(fabric.prefix(1)) : fabric {
        context.addPath(shape.path)
        context.setFillColor(color(monochrome ? "#151923" : shape.color))
        context.fillPath()
    }
    for (x, y, r, hex) in circles {
        context.setFillColor(color(monochrome ? "#151923" : hex))
        context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}
func svg(monochrome: Bool) -> String {
    let paths = (monochrome ? Array(fabric.prefix(1)) : fabric).map {
        "  <path d=\"\($0.svg)\" fill=\"\(monochrome ? "currentColor" : $0.color)\"/>"
    }
    let dots = circles.map { x, y, r, hex in
        "  <circle cx=\"\(x)\" cy=\"\(y)\" r=\"\(r)\" fill=\"\(monochrome ? "currentColor" : hex)\"/>"
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 256" role="img" aria-labelledby="title">
      <title id="title">Headroom — Balanced hammock</title>
    \((paths + dots).joined(separator: "\n"))
    </svg>

    """
}
func png(size: Int, icon: Bool, monochrome: Bool = false, to url: URL) throws {
    let height = icon ? size : Int(Double(size) * 0.8)
    let context = CGContext(data: nil, width: size, height: height, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: CGFloat(size) / (icon ? 1024 : 320), y: -CGFloat(size) / (icon ? 1024 : 320))
    if icon {
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 184, cornerHeight: 184, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(gray: 0, alpha: 0.14))
        context.addPath(tile); context.setFillColor(color("#FBFAF7")); context.fillPath()
        context.restoreGState()
        context.addPath(tile); context.setStrokeColor(color("#E9E8E3")); context.setLineWidth(2); context.strokePath()
        context.translateBy(x: 112, y: 168)
        context.scaleBy(x: 2.5, y: 2.5)
    }
    mark(context, monochrome: monochrome)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift scripts/generate-brand.swift output-directory") }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: root, withIntermediateDirectories: true)
try svg(monochrome: false).write(to: root.appendingPathComponent("headroom.svg"), atomically: true, encoding: .utf8)
try svg(monochrome: true).write(to: root.appendingPathComponent("headroom-monochrome.svg"), atomically: true, encoding: .utf8)
try png(size: 1024, icon: false, to: root.appendingPathComponent("headroom.png"))
try png(size: 1024, icon: true, to: root.appendingPathComponent("headroom-app-icon.png"))
let iconset = root.appendingPathComponent("Headroom.iconset", isDirectory: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(size: points * scale, icon: true, to: iconset.appendingPathComponent(filename))
    }
}
print("Generated Balanced SVG, PNG and complete iconset in \(root.path)")
