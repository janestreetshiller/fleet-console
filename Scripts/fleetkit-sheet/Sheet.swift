import AppKit
import CoreImage
import SwiftUI
import FleetCore

// A contact sheet of the real FleetKit primitives. The design files are
// symlinked into this target, not copied, so what renders here is what ships.

// MARK: - Sheet content

struct Row<Content: View>: View {
    let name: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(name)
                .font(FleetFont.mono(10))
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }
}

struct Group_<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(FleetFont.sectionLabel)
                .foregroundStyle(.tertiary)
                .kerning(0.8)
            content
        }
    }
}

let tones: [(String, StatusTone)] = [
    ("good", .good), ("warn", .warn), ("bad", .bad),
    ("neutral", .neutral), ("unknown", .unknown),
]

func evidence(_ kind: Int) -> (Evidence, HealthSpec) {
    switch kind {
    case 0: return (Evidence(processExists: true, listeningPorts: [8787], portScanRan: true,
                             healthCheckRan: true, healthPassed: true,
                             healthDetail: "200 in 12 ms"),
                    HealthSpec(kind: .http, target: "http://127.0.0.1:8787/healthz"))
    case 1: return (Evidence(processExists: true, listeningPorts: [], portScanRan: true,
                             healthCheckRan: true, healthPassed: false,
                             healthDetail: "connection refused"),
                    HealthSpec(kind: .http, target: "http://127.0.0.1:8787/healthz"))
    default: return (Evidence(processExists: true), HealthSpec(kind: .none))
    }
}

let topology = CPUTopology(brand: "Apple M-series", logicalCores: 10,
                           efficiencyCores: 4, performanceCores: 6,
                           efficiencyRange: 0..<4, performanceRange: 4..<10)
let coreValues: [Double] = [0.12, 0.30, 0.08, 0.21, 0.94, 0.77, 0.55, 0.18, 0.42, 0.05]

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Group_(title: "StatusTone — symbol (enclosed) vs verdict (bare)") {
                Row(name: "StatusDot") {
                    HStack(spacing: 22) {
                        ForEach(tones, id: \.0) { name, tone in
                            VStack(spacing: 3) {
                                StatusDot(tone: tone)
                                Text(name).font(FleetFont.micro).foregroundStyle(.tertiary)
                            }.frame(width: 54)
                        }
                    }
                }
                Row(name: "verdict") {
                    HStack(spacing: 22) {
                        ForEach(tones, id: \.0) { _, tone in
                            Image(systemName: tone.verdict)
                                .font(FleetFont.micro.weight(.bold))
                                .foregroundStyle(tone.color)
                                .frame(width: 54)
                        }
                    }
                }
                Row(name: "StatusPip") {
                    HStack(spacing: 22) {
                        ForEach(tones, id: \.0) { _, tone in
                            StatusPip(tone: tone).frame(width: 54)
                        }
                    }
                }
            }

            Group_(title: "EntityIcon — badge containment at every size") {
                Row(name: "unbadged") {
                    HStack(spacing: 14) {
                        EntityIcon(symbol: "server.rack", tone: .good, size: FleetMetrics.iconCompact)
                        EntityIcon(symbol: "curlybraces", tone: .warn, size: FleetMetrics.iconRow)
                        EntityIcon(symbol: "hexagon", tone: .bad, size: FleetMetrics.iconRowLarge)
                        EntityIcon(symbol: "cylinder.split.1x2", tone: .neutral, size: FleetMetrics.iconInspector)
                    }
                }
                Row(name: "badged") {
                    HStack(spacing: 14) {
                        EntityIcon(symbol: "server.rack", tone: .good, size: FleetMetrics.iconCompact, badge: .good)
                        EntityIcon(symbol: "curlybraces", tone: .warn, size: FleetMetrics.iconRow, badge: .warn)
                        EntityIcon(symbol: "hexagon", tone: .bad, size: FleetMetrics.iconRowLarge, badge: .bad)
                        EntityIcon(symbol: "cylinder.split.1x2", tone: .neutral, size: FleetMetrics.iconInspector, badge: .unknown)
                    }
                }
                // The alignment proof: badged and unbadged rows must start on the
                // same vertical. A hairline behind both makes any drift visible.
                Row(name: "left edge") {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(ConsoleColor.hairlineStrong).frame(width: 1)
                        VStack(alignment: .leading, spacing: 3) {
                            EntityIcon(symbol: "server.rack", tone: .good, size: FleetMetrics.iconRowLarge)
                            EntityIcon(symbol: "server.rack", tone: .good, size: FleetMetrics.iconRowLarge, badge: .bad)
                        }
                    }
                }
            }

            // A faithful stand-in for DeviceNodeRow: same EntityIcon call, same
            // trailing pip and latency badge, same detail line that states the
            // path and not the health. This is the row the sidebar is made of.
            Group_(title: "Fleet sidebar node — health must survive desaturation") {
                ForEach(Array(zip(["studio", "mini", "nas", "laptop"],
                                  [DeviceHealth.reachable, .partial, .unreachable, .unknown])), id: \.0) { name, health in
                    Row(name: "\(health)") {
                        HStack(spacing: 10) {
                            EntityIcon(symbol: "desktopcomputer",
                                       tone: health.tone,
                                       size: FleetMetrics.iconRowLarge,
                                       badge: health == .reachable ? nil : health.tone)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(ConsoleFont.rowTitle.weight(.medium))
                                Text("Mac Studio · tailnet · ssh :22")
                                    .font(ConsoleFont.caption).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 3) {
                                StatusPip(tone: health.tone, size: 7, pulsing: false)
                                if health != .unreachable {
                                    ConsoleBadge(text: "14 ms", tone: .good)
                                }
                            }
                        }
                        .frame(width: 240)
                    }
                }
            }

            Group_(title: "EvidenceChips — the honesty component") {
                Row(name: "verified") { EvidenceChips(evidence: evidence(0).0, health: evidence(0).1) }
                Row(name: "failing")  { EvidenceChips(evidence: evidence(1).0, health: evidence(1).1) }
                Row(name: "unverifiable + stale") {
                    EvidenceChips(evidence: evidence(2).0, health: evidence(2).1, stale: true)
                }
            }

            Group_(title: "Rows") {
                Row(name: "FleetRowLabel") {
                    FleetRowLabel(icon: "server.rack", tone: .good, badge: nil,
                                  title: "api", subtitle: "claude · local API for triage",
                                  trailingText: "1h 42m", trailingMono: true)
                        .frame(width: 340)
                }
                Row(name: "+ badge") {
                    FleetRowLabel(icon: "curlybraces", tone: .bad, badge: .bad,
                                  title: "worker", subtitle: "health check failing",
                                  trailingText: "expired", trailingMono: true)
                        .frame(width: 340)
                }
            }

            Group_(title: "Meters, tags, badges") {
                Row(name: "Meter") {
                    HStack(spacing: 18) {
                        Meter(value: 0.18, tone: .good, caption: "18%")
                        Meter(value: 0.82, tone: .warn, caption: "82%")
                        Meter(value: 0.96, tone: .bad, caption: "96%")
                        Meter(value: nil, tone: .neutral, caption: "—")
                    }
                }
                Row(name: "CoreGrid") { CoreGrid(values: coreValues, topology: topology) }
                Row(name: "Tag") {
                    HStack(spacing: 8) {
                        ForEach(tones, id: \.0) { name, tone in Tag(text: name, tone: tone) }
                    }
                }
                // Regression case. A chip in a row accessory competes with a title
                // that holds layoutPriority(1); squeeze the row and the loser is
                // the chip. Unconstrained it compresses by *wrapping*, one
                // character per line, which is what turned "Unmanaged" into a
                // four-line orange block in the popover.
                // The real UnmanagedRowView, at the real popover width, with the
                // real strings. The long subtitle is the whole mechanism: its
                // VStack holds layoutPriority(1), so it claims the width first
                // and the accessory gets whatever is left.
                Row(name: "unmanaged row") {
                    FleetRowLabel(icon: "curlybraces",
                                  tone: .warn,
                                  title: "Python",
                                  subtitle: "pid 54610 · first seen 13h 17m ago") {
                        Tag(text: "Unmanaged", tone: .warn)
                        Text(":8765")
                            .font(FleetFont.mono())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: FleetMetrics.popoverWidth - 60)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ConsoleColor.hairlineStrong))
                }
                Row(name: "ConsoleBadge") {
                    HStack(spacing: 8) {
                        ConsoleBadge(text: "3", tone: .neutral)
                        ConsoleBadge(text: "12 ms", tone: .good, symbol: "bolt.fill")
                        ConsoleBadge(text: "2", tone: .warn)
                        ConsoleBadge(text: "1", tone: .bad)
                    }
                }
                Row(name: "Sparkline") {
                    HStack(spacing: 18) {
                        Sparkline(values: [0.1,0.3,0.2,0.6,0.4,0.8,0.5], tone: .good,
                                  label: "CPU", current: "4.2%")
                        Sparkline(values: [0.5,0.5,0.6,0.55,0.7,0.62,0.68], tone: .neutral,
                                  label: "MEM", current: "812 MB")
                    }
                }
                Row(name: "TelemetrySeries") {
                    HStack(spacing: 18) {
                        ForEach(TelemetrySeries.allCases) { s in
                            HStack(spacing: 5) {
                                Swatch(color: s.color)
                                Text(s.label).font(ConsoleFont.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Row(name: "ConnectionPip") { ConnectionPip(connected: true, label: "controller · 4 services") }
            }

            Group_(title: "StorageCategory") {
                Row(name: "bar order") {
                    HStack(spacing: 0) {
                        ForEach(StorageCategory.allCases) { c in
                            Rectangle().fill(c.color).frame(width: 34, height: 16)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ConsoleMetrics.barCorner, style: .continuous))
                }
                Row(name: "legend") {
                    HStack(spacing: 10) {
                        ForEach(StorageCategory.allCases) { c in
                            HStack(spacing: 3) {
                                Image(systemName: c.symbol).font(ConsoleFont.marker).foregroundStyle(c.color)
                                Text(c.rawValue).font(FleetFont.micro).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 1000, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Render

/// Strips hue, keeping luminance. `accessibilityDifferentiateWithoutColor` is a
/// read-only environment value, so it cannot be injected into a render — but the
/// question that flag exists to answer is "does this still read without hue",
/// and desaturating the finished pixels answers it directly and more honestly.
func desaturated(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
    guard let ci = CIImage(bitmapImageRep: rep),
          let f = CIFilter(name: "CIColorControls") else { return nil }
    f.setValue(ci, forKey: kCIInputImageKey)
    f.setValue(0.0, forKey: kCIInputSaturationKey)
    guard let out = f.outputImage else { return nil }
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
    return NSBitmapImageRep(cgImage: cg)
}

@MainActor
func render(_ appearance: NSAppearance.Name, tag: String, to dir: URL) {
    let app = NSAppearance(named: appearance)!
    var image: NSImage?
    app.performAsCurrentDrawingAppearance {
        let r = ImageRenderer(content:
            Sheet().environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
        )
        r.scale = 2
        image = r.nsImage
    }
    guard let image, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        print("render failed: \(tag)"); return
    }
    func write(_ r: NSBitmapImageRep, _ name: String) {
        guard let png = r.representation(using: .png, properties: [:]) else { return }
        let url = dir.appendingPathComponent(name)
        try? png.write(to: url)
        print("wrote \(name)  \(r.pixelsWide)x\(r.pixelsHigh)")
    }
    write(rep, "fleetkit-\(tag).png")
    if let grey = desaturated(rep) { write(grey, "fleetkit-\(tag)-greyscale.png") }
}

@main
struct Main {
    @MainActor static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
                      ? CommandLine.arguments[1] : ".")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        render(.aqua, tag: "light", to: out)
        render(.darkAqua, tag: "dark", to: out)
    }
}
