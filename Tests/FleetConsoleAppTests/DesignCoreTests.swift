import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import FleetConsoleApp

@Suite(.serialized)
struct DesignCoreTests {
    @MainActor @Test("Fleet uses the shared signal instead of an appearance-dependent accent")
    func canonicalSignal() throws {
        let color = try #require(NSColor(SketchInk.accent).usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 241.0 / 255.0) < 0.00001)
        #expect(abs(color.greenComponent - 123.0 / 255.0) < 0.00001)
        #expect(abs(color.blueComponent - 51.0 / 255.0) < 0.00001)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try Data(contentsOf: root.appendingPathComponent(".design-core/core.json"))
        let core = try #require(JSONSerialization.jsonObject(with: source) as? [String: Any])
        let version = try #require(core["version"] as? String)
        let digest = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        #expect(OurosCoreTokens.version == version)
        #expect(OurosCoreTokens.sourceSHA256 == digest)
    }

    @MainActor @Test("Shared filled actions retain white ink with normal-text contrast")
    func actionContrast() throws {
        let background = try #require(NSColor(FleetCorePalette.actionBackground).usingColorSpace(.sRGB))
        let foreground = try #require(NSColor(FleetCorePalette.actionForeground).usingColorSpace(.sRGB))
        func luminance(_ color: NSColor) -> Double {
            func channel(_ c: CGFloat) -> Double {
                let value = Double(c)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.redComponent)
                + 0.7152 * channel(color.greenComponent)
                + 0.0722 * channel(color.blueComponent)
        }
        let ratio = (luminance(foreground) + 0.05) / (luminance(background) + 0.05)
        #expect(ratio >= 4.5)
        #expect(foreground.redComponent == 1)
        #expect(foreground.greenComponent == 1)
        #expect(foreground.blueComponent == 1)
    }

    @MainActor @Test("Shared primary actions render in both appearances and unavailable state", .enabled(if: ProcessInfo.processInfo.environment["FLEET_DESIGN_CORE_CAPTURE_DIR"] != nil))
    func primaryActionRender() throws {
        guard let path = ProcessInfo.processInfo.environment["FLEET_DESIGN_CORE_CAPTURE_DIR"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        // Offscreen rendering still creates windows; .prohibited disallows them.
        NSApp.setActivationPolicy(.accessory)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for enabled in [true, false] {
                let view = NSHostingView(rootView:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Fleet Console").font(.headline)
                        Button("Link Device") {}.fleetPrimaryAction().disabled(!enabled)
                        Text(enabled ? "Ready to link this device." : "Connect to continue.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(width: 320, height: 160, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor))
                )
                let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 320, height: 160),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                view.appearance = window.appearance
                window.contentView = view
                window.orderBack(nil)
                defer { window.orderOut(nil) }
                view.layoutSubtreeIfNeeded()
                let until = Date().addingTimeInterval(0.2)
                while Date() < until {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                bitmap.size = view.bounds.size
                view.setNeedsDisplay(view.bounds)
                window.displayIfNeeded()
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("primary-action-\(name)-\(enabled ? "enabled" : "disabled").png"))
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                var fillCount = 0
                var minX = bitmap.pixelsWide
                var minY = bitmap.pixelsHigh
                var maxX = 0
                var maxY = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if color.redComponent > color.greenComponent + 0.15,
                           color.greenComponent > color.blueComponent + 0.05 {
                            fillCount += 1
                            minX = min(minX, x)
                            minY = min(minY, y)
                            maxX = max(maxX, x)
                            maxY = max(maxY, y)
                        }
                    }
                }
                try #require(fillCount > 100, "An enabled or unavailable primary action must actually paint the core orange fill, including an inactive window")
                var whiteInkCount = 0
                for y in minY...maxY {
                    for x in minX...maxX {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95 {
                            whiteInkCount += 1
                        }
                    }
                }
                #expect(whiteInkCount > 5, "The rendered primary action keeps explicit white label ink in every appearance and availability state")
            }
        }
    }

    @MainActor @Test("Primary action styling preserves real activation and unavailable behavior")
    func primaryActionActivation() throws {
        _ = NSApplication.shared
        // Permit the offscreen test window without activating the application.
        NSApp.setActivationPolicy(.accessory)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        for enabled in [true, false] {
            var activations = 0
            let view = NSHostingView(rootView: Button("Run") { activations += 1 }
                .fleetPrimaryAction()
                .disabled(!enabled)
                .frame(width: 200, height: 100))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 100),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            window.orderBack(nil)
            defer { window.orderOut(nil) }
            view.layoutSubtreeIfNeeded()
            let until = Date().addingTimeInterval(0.1)
            while Date() < until {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            try sendSyntheticClick(at: NSPoint(x: 100, y: 50), in: window)
            #expect(activations == (enabled ? 1 : 0))
        }
    }

    @MainActor @Test("Core adoption keeps the native surface and component dimensions")
    func nativeSurfaceRemainsNative() throws {
        let actual = try #require(NSColor(SketchInk.ground).usingColorSpace(.sRGB))
        let expected = try #require(NSColor.windowBackgroundColor.usingColorSpace(.sRGB))
        #expect(abs(actual.redComponent - expected.redComponent) < 0.00001)
        #expect(abs(actual.greenComponent - expected.greenComponent) < 0.00001)
        #expect(abs(actual.blueComponent - expected.blueComponent) < 0.00001)
        #expect(FleetMetrics.compactRowHeight == 36)
        #expect(ConsoleMetrics.cardPadding == 13)
    }
}
