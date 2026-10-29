// satellite.swift <lat> <lon> <spanMeters> <widthPx> <heightPx> <out.png> [heading]
// Renders a real Apple Maps satellite snapshot (no UI, no API key) for ad backgrounds.
// Keep the "Maps" attribution: the template prints it in a corner.
import Foundation
import MapKit
import AppKit

let a = CommandLine.arguments
guard a.count >= 7, let lat = Double(a[1]), let lon = Double(a[2]), let span = Double(a[3]),
      let w = Double(a[4]), let h = Double(a[5]) else {
    FileHandle.standardError.write("usage: satellite.swift lat lon spanMeters w h out.png [heading]\n".data(using: .utf8)!)
    exit(2)
}
let out = URL(fileURLWithPath: a[6])
let heading = a.count > 7 ? Double(a[7]) ?? 0 : 0

let opts = MKMapSnapshotter.Options()
let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
// Camera rather than region so the span is exact in metres and heading can rotate the road.
let cam = MKMapCamera(lookingAtCenter: center, fromDistance: span * 1.2, pitch: 0, heading: heading)
opts.camera = cam
opts.mapType = .satellite
opts.size = NSSize(width: w, height: h)   // a CLI process renders at 1x, so points == pixels
opts.appearance = NSAppearance(named: .darkAqua)
if #available(macOS 14.0, *) { opts.preferredConfiguration = MKImageryMapConfiguration() }

let done = DispatchSemaphore(value: 0)
MKMapSnapshotter(options: opts).start(with: DispatchQueue.global()) { snap, err in
    defer { done.signal() }
    guard let snap else { FileHandle.standardError.write("snapshot failed: \(String(describing: err))\n".data(using: .utf8)!); exit(1) }
    let img = snap.image
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: out)
    print(out.path, rep.pixelsWide, "x", rep.pixelsHigh)
}
done.wait()
