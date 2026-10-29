// recolor_ring.swift <in.png> <out.png> <cx> <cy> <rInner> <rOuter> <hex> [strokeIn strokeOut glowR]
// Recolours the lime rider-marker ring of a real screenshot to another colour, touching only
// pixels inside the annulus rInner..rOuter (source pixels) around (cx, cy) that contain lime.
// Each pixel keeps its own anti-aliasing: we swap only the lime component
// (out = px + a * (target - lime)), so edges and the dark marker fill stay untouched.
// Optional bold mode: also paint a solid, anti-aliased ring strokeIn..strokeOut in the same
// colour (a thicker version of the marker's own ring, drawn on the same centre) and a soft glow
// fading out to glowR, so the marker stands out at phone size. Keep strokeIn clear of the
// initial letter (rider marker letter fits inside ~r 20).
// Writes a NEW file; the original screenshot is never modified.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 8 || a.count == 11, let cx = Double(a[3]), let cy = Double(a[4]), let rIn = Double(a[5]), let rOut = Double(a[6]) else {
    FileHandle.standardError.write("usage: recolor_ring.swift in.png out.png cx cy rInner rOuter RRGGBB\n".data(using: .utf8)!); exit(2)
}
let hex = UInt32(a[7].trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFF8A4C
let target = (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
let lime = (205.0, 239.0, 30.0)   // DS.Accent.base #CDEF1E
let bgLevel = 24.0                // marker fill / map background, ~#181818

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

var changed = 0
for y in max(0, Int(cy - rOut - 1))...min(h - 1, Int(cy + rOut + 1)) {
    for x in max(0, Int(cx - rOut - 1))...min(w - 1, Int(cx + rOut + 1)) {
        let d = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
        guard d >= rIn && d <= rOut else { continue }
        let i = (y * w + x) * 4   // context rows are top-down in memory
        let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
        // Lime-ish only: green dominant over blue, red not above green (excludes white text/grey).
        guard g > b + 30, g >= r, g > bgLevel + 10 else { continue }
        let k = max(0, min(1, (g - bgLevel) / (lime.1 - bgLevel)))
        let nr = r + k * (target.0 - lime.0), ng = g + k * (target.1 - lime.1), nb = b + k * (target.2 - lime.2)
        px[i] = UInt8(max(0, min(255, nr))); px[i + 1] = UInt8(max(0, min(255, ng))); px[i + 2] = UInt8(max(0, min(255, nb)))
        changed += 1
    }
}
if a.count == 11, let sIn = Double(a[8]), let sOut = Double(a[9]), let gR = Double(a[10]) {
    // Over-composite: coverage from the analytic distance to the band edges (1 px AA), glow as
    // a squared falloff outside the stroke.
    for y in max(0, Int(cy - gR - 1))...min(h - 1, Int(cy + gR + 1)) {
        for x in max(0, Int(cx - gR - 1))...min(w - 1, Int(cx + gR + 1)) {
            let d = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
            var cov = max(0, min(1, min(d - sIn + 0.5, sOut - d + 0.5)))
            if d > sOut && d < gR { let t = (d - sOut) / (gR - sOut); cov = max(cov, 0.45 * (1 - t) * (1 - t)) }
            guard cov > 0 else { continue }
            let i = (y * w + x) * 4
            px[i]     = UInt8(max(0, min(255, Double(px[i])     * (1 - cov) + target.0 * cov)))
            px[i + 1] = UInt8(max(0, min(255, Double(px[i + 1]) * (1 - cov) + target.1 * cov)))
            px[i + 2] = UInt8(max(0, min(255, Double(px[i + 2]) * (1 - cov) + target.2 * cov)))
            changed += 1
        }
    }
}
let outImg = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, outImg, nil)
CGImageDestinationFinalize(dest)
print(a[2], "pixels recoloured:", changed)
