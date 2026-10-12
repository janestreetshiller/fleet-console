import AppKit
import Foundation

// FleetConsole's app icon: the blackletter F printed on a sheet of paper.
//
// The F is `Sources/FleetConsoleApp/Brand/fleet-letter.png` — the same file the
// window and the popover draw their mark from — so the Finder icon and the
// in-app mark are one letter, not two drawings of one. It is ink on a
// transparent ground, so the plate supplies the paper and the icon stays crisp
// on any background the Dock or Finder puts behind it. Every size is drawn at
// its own scale rather than downsampled from 1024.

guard CommandLine.arguments.count > 2,
      let letter = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
    FileHandle.standardError.write("usage: Icon.swift <iconset dir> <fleet-letter.png>\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Plate

/// A superellipse. `NSBezierPath(roundedRect:)` draws circular arcs, which read
/// visibly pinched against macOS's own continuous corners at 512pt and up.
func squircle(in rect: CGRect, n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 1440
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = rect.midY + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.line(to: CGPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

/// macOS ships app icons as an 824pt plate inside a 1024pt canvas.
func plateRect(canvas: CGFloat) -> CGRect {
    let inset = (canvas * 200 / 1024 / 2).rounded()
    return CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// MARK: - Drawing helpers

func clipped(to path: NSBezierPath, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func shadowed(_ blur: CGFloat, _ dy: CGFloat, _ color: NSColor, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.shadowColor = color
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func gradient(_ colors: [NSColor], at locations: [CGFloat]? = nil,
              in rect: CGRect, angle: CGFloat) {
    let g = locations.map { NSGradient(colors: colors, atLocations: $0, colorSpace: .sRGB)! }
        ?? NSGradient(colors: colors)!
    g.draw(in: rect, angle: angle)
}

// MARK: - Palette

let paperTop = rgb(251, 247, 238)
let paperBottom = rgb(239, 231, 216)

// MARK: - The icon

func drawIcon(canvas: CGRect) {
    let c = canvas.width
    let rect = plateRect(canvas: c)
    let plate = squircle(in: rect)

    // Lifted off the desktop the way every macOS icon plate is.
    shadowed(c * 0.022, -c * 0.009, rgb(0, 0, 0, 0.30)) {
        paperBottom.setFill()
        plate.fill()
    }
    clipped(to: plate) {
        gradient([paperTop, paperBottom], in: rect, angle: -90)
    }

    let height = rect.height * 0.72
    let width = height * letter.size.width / letter.size.height
    letter.draw(in: CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height),
                from: .zero, operation: .sourceOver, fraction: 1)

    clipped(to: plate) {
        let rim = plate.copy() as! NSBezierPath
        rim.lineWidth = max(1, c * 0.006)
        rgb(0, 0, 0, 0.14).setStroke()
        rim.stroke()
    }
}

// MARK: - Output

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.setAllowsAntialiasing(true)
    ctx.imageInterpolation = .high
    drawIcon(canvas: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Every slot `iconutil` expects. Each one is *drawn* at its own size rather
/// than downsampled from 1024, which is the whole point of the detail ramp.
let slots: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for (name, size) in slots {
    let data = render(size: size).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    print("  \(name)")
}
