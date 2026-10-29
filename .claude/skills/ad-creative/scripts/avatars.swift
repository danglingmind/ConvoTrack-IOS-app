// avatars.swift <in.png> <out.png> <cx,cy,r,image> [<cx,cy,r,image> ...]
// Puts profile photos into a real screenshot's letter-avatar circles, the way the app itself
// draws a rider who has a photo (GoogleMapView.renderRiderIcon: aspect-fill, clipped to the
// circle, ring drawn on top). r = the INNER radius of the circle in source pixels, i.e. inside
// the lime ring, so the app's ring, name tag and distance label stay exactly as captured.
// image = path to the portrait, or "TEST" to paint a translucent magenta disc for checking the
// alignment before any portraits exist. Writes a NEW file; the original is never modified.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 4 else {
    FileHandle.standardError.write("usage: avatars.swift in.png out.png cx,cy,r,image ...\n".data(using: .utf8)!); exit(2)
}
func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
guard let base = load(a[1]) else { FileHandle.standardError.write("cannot read \(a[1])\n".data(using: .utf8)!); exit(1) }
let w = base.width, h = base.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))

for spec in a[3...] {
    let p = spec.split(separator: ",", maxSplits: 3).map(String.init)
    guard p.count == 4, let cx = Double(p[0]), let cy = Double(p[1]), let r = Double(p[2]) else {
        FileHandle.standardError.write("bad spec \(spec)\n".data(using: .utf8)!); exit(2)
    }
    // CoreGraphics' origin is bottom-left; screenshot coordinates are top-left.
    let circle = CGRect(x: cx - r, y: Double(h) - cy - r, width: 2 * r, height: 2 * r)
    ctx.saveGState()
    ctx.addEllipse(in: circle); ctx.clip()
    if p[3] == "TEST" {
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 0.6)); ctx.fill(circle)
    } else {
        guard let img = load(p[3]) else { FileHandle.standardError.write("cannot read \(p[3])\n".data(using: .utf8)!); exit(1) }
        // Aspect-fill, biased slightly up so a head-and-shoulders portrait keeps the face centred.
        let s = max(circle.width / Double(img.width), circle.height / Double(img.height))
        let dw = Double(img.width) * s, dh = Double(img.height) * s
        ctx.draw(img, in: CGRect(x: circle.midX - dw / 2, y: circle.midY - dh / 2 - (dh - circle.height) * 0.12,
                                 width: dw, height: dh))
    }
    ctx.restoreGState()
}
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print(a[2], "avatars:", a.count - 3)
