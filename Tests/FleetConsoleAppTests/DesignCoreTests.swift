import AppKit
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
        #expect(OurosCoreTokens.version == "1.1.0")
        #expect(OurosCoreTokens.sourceSHA256.count == 64)
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
                view.layoutSubtreeIfNeeded()
                let until = Date().addingTimeInterval(0.2)
                while Date() < until {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("primary-action-\(name)-\(enabled ? "enabled" : "disabled").png"))
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                window.orderOut(nil)
            }
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
