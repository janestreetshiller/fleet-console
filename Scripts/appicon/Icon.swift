import AppKit
import Foundation

// FleetConsole's app icon, drawn rather than exported.
//
// The mark is the one in `MenuBarItem.swift` — stem, long top arm, short middle
// arm, rounded caps — at its exact proportions, so the Finder icon and the
// menu-bar glyph are the same letter and not two drawings of one. Behind it,
// the fleet mesh: concentric arcs struck from the stem's foot, with nodes
// sitting on them.
//
// Detail is a function of size. A 16pt icon that carries seven arcs and four
// nodes is not a small icon, it is a grey smudge — so the mesh thins out and
// then drops entirely as the canvas shrinks, and below 32pt only the letter is
// left. That is the same reasoning as `MenuBarItem`'s geometric F: a mark has to
// survive the size it is actually used at.

// MARK: - The mark

enum Mark {
    static let barRatio: CGFloat = 2.4 / 15
    static let stem = CGRect(x: 2.2 / 15, y: 1.2 / 15, width: 2.4 / 15, height: 12.6 / 15)
    static let topArm = CGRect(x: 3.4 / 15, y: 11.4 / 15, width: 9.2 / 15, height: 2.4 / 15)
    static let midArm = CGRect(x: 3.4 / 15, y: 6.4 / 15, width: 6.7 / 15, height: 2.4 / 15)

    /// The ink, not the cell it was drawn in. An F fills 0.69 × 0.84 of its 15pt
    /// box, so centring the *box* puts the letter visibly low and left.
    static let ink = CGRect(x: stem.minX, y: stem.minY,
                            width: topArm.maxX - stem.minX,
                            height: topArm.maxY - stem.minY)

    private static func fit(_ box: CGRect) -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(box.width / ink.width, box.height / ink.height)
        return (scale, CGPoint(x: box.midX - ink.width * scale / 2 - ink.minX * scale,
                               y: box.midY - ink.height * scale / 2 - ink.minY * scale))
    }

    static func bar(in box: CGRect) -> CGFloat { barRatio * fit(box).scale }

    /// The foot of the stem — where the mesh is struck from.
    static func foot(in box: CGRect) -> CGPoint {
        let (scale, origin) = fit(box)
        return CGPoint(x: origin.x + (stem.minX + barRatio / 2) * scale,
                       y: origin.y + stem.minY * scale)
    }

    static func path(in box: CGRect) -> NSBezierPath {
        let (scale, origin) = fit(box)
        let path = NSBezierPath()
        for r in [stem, topArm, midArm] {
            let s = CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale,
                           width: r.width * scale, height: r.height * scale)
            let radius = min(s.width, s.height) / 2
            path.append(NSBezierPath(roundedRect: s, xRadius: radius, yRadius: radius))
        }
        return path
    }
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
//
// The accents are FleetKit's own status vocabulary: `good` green and `warn`
// amber from `StatusTone`, with the mesh in the cyan the console uses for
// telemetry. A node on the mesh is a device, and it is the colour its state
// would be anywhere else in the app.

let meshCyan = rgb(0, 224, 255)
let nodeGood = rgb(48, 209, 118)
let nodeWarn = rgb(255, 173, 40)
let markInk = rgb(250, 252, 255)

// MARK: - Size-dependent detail

struct Detail {
    var rings: Int
    var nodes: [(ring: Int, degrees: CGFloat, color: NSColor)]
    var meshAlpha: CGFloat
    var bevel: Bool

    /// Node placement is constrained from both sides. Rings 1–2 pass under the
    /// arms, so a node there lands on the letterform. And the foot sits low-left,
    /// so a ring only stays on the plate up to an angle that shrinks as it grows:
    /// ring 5 at 22° exits past the right edge, which is how the first pass lost
    /// its amber node entirely. Each node below is placed at an angle its own
    /// ring can still reach — low on the near rings, high on the far one.
    static func forCanvas(_ canvas: CGFloat) -> Detail {
        switch canvas {
        case 512...:
            return Detail(rings: 7,
                          nodes: [(3, 12, nodeGood), (4, 38, nodeWarn),
                                  (5, 60, meshCyan)],
                          meshAlpha: 0.62, bevel: true)
        case 128..<512:
            return Detail(rings: 6,
                          nodes: [(3, 12, nodeGood), (4, 38, nodeWarn)],
                          meshAlpha: 0.70, bevel: true)
        case 48..<128:
            return Detail(rings: 4, nodes: [], meshAlpha: 0.72, bevel: true)
        default:
            // 16 and 32: the letter alone. Arcs at this size are one grey pixel
            // wide and read as dirt on the plate.
            return Detail(rings: 0, nodes: [], meshAlpha: 0, bevel: false)
        }
    }
}

// MARK: - The icon

func drawIcon(canvas: CGRect) {
    let c = canvas.width
    let rect = plateRect(canvas: c)
    let plate = squircle(in: rect)
    let detail = Detail.forCanvas(c)

    clipped(to: plate) {
        gradient([rgb(20, 26, 40), rgb(6, 8, 13)], in: rect, angle: -90)
    }

    // The letter's box. Held off the plate edge by 21% so the mesh has a corner
    // to come from.
    let box = rect.insetBy(dx: c * 0.21, dy: c * 0.21)
    let foot = Mark.foot(in: box)

    if detail.rings > 0 {
        clipped(to: plate) {
            let spacing = rect.width * 0.155
            for i in 1...detail.rings {
                let arc = NSBezierPath()
                // Stopping at 72° keeps every arc in the quadrant right of the
                // stem. Sweeping to 90°+ sent each one over the top of the
                // letter and back out on its left, as a stub with no visible
                // origin.
                arc.appendArc(withCenter: foot, radius: spacing * CGFloat(i),
                              startAngle: -4, endAngle: 72)
                arc.lineWidth = max(1, c * 0.011)
                arc.lineCapStyle = .round
                meshCyan.withAlphaComponent(detail.meshAlpha * max(0, 1 - CGFloat(i - 1) * 0.11))
                    .setStroke()
                arc.stroke()
            }
            for node in detail.nodes {
                let radius = spacing * CGFloat(node.ring)
                let radians = node.degrees * .pi / 180
                let p = CGPoint(x: foot.x + cos(radians) * radius,
                                y: foot.y + sin(radians) * radius)
                let dot = c * 0.016
                shadowed(c * 0.022, 0, node.color.withAlphaComponent(0.85)) {
                    node.color.setFill()
                    NSBezierPath(ovalIn: CGRect(x: p.x - dot, y: p.y - dot,
                                                width: dot * 2, height: dot * 2)).fill()
                }
            }
        }
    }

    // A gap between the arcs and the letter. The inner rings pass behind the
    // mark and re-emerge between the stem and the middle arm, where a 4pt teal
    // segment reads as a scratch on the letter rather than as an arc continuing
    // behind it. Repainting the plate's own gradient through a fattened copy of
    // the mark clears that band without leaving a visible outline.
    if detail.rings > 0 {
        let halo = NSBezierPath(cgPath: Mark.path(in: box).cgPath
            .copy(strokingWithWidth: c * 0.030, lineCap: .round, lineJoin: .round, miterLimit: 10))
        clipped(to: halo) {
            gradient([rgb(20, 26, 40), rgb(6, 8, 13)], in: rect, angle: -90)
        }
    }

    if detail.bevel {
        clipped(to: plate) {
            gradient([rgb(255, 255, 255, 0.10), .clear],
                     in: CGRect(x: rect.minX, y: rect.midY,
                                width: rect.width, height: rect.height / 2), angle: -90)
        }
        clipped(to: plate) {
            let ring = plate.copy() as! NSBezierPath
            ring.lineWidth = max(1, c * 0.006)
            rgb(255, 255, 255, 0.24).setStroke()
            ring.stroke()
        }
    }

    // The letter last, over everything, with a shadow deep enough to hold it off
    // the arcs it crosses.
    shadowed(c * 0.055, -c * 0.008, rgb(0, 0, 0, 0.9)) {
        markInk.setFill()
        Mark.path(in: box).fill()
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
