import Foundation
import CoreGraphics
// usage: drag <x1> <y1> <x2> <y2> [steps] [holdMs]
let a = CommandLine.arguments
guard a.count >= 5, let x1=Double(a[1]), let y1=Double(a[2]), let x2=Double(a[3]), let y2=Double(a[4]) else { exit(2) }
let steps = a.count > 5 ? Int(a[5]) ?? 25 : 25
let hold  = a.count > 6 ? UInt32(a[6]) ?? 40 : 40
func post(_ t: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved, CGPoint(x:x1,y:y1)); usleep(50_000)
post(.leftMouseDown, CGPoint(x:x1,y:y1)); usleep(hold*1000)
for i in 1...steps {
    let t = Double(i)/Double(steps)
    post(.leftMouseDragged, CGPoint(x: x1+(x2-x1)*t, y: y1+(y2-y1)*t))
    usleep(8_000)
}
usleep(hold*1000)
post(.leftMouseUp, CGPoint(x:x2,y:y2))
