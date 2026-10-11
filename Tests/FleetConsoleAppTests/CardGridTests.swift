import AppKit
import SwiftUI
import Testing
@testable import FleetConsoleApp

private struct CardFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
private final class FrameCapture {
    var frames: [String: CGRect] = [:]
}

@Observable
@MainActor
private final class ChangingCards {
    var count = 5
    var contentHeight: CGFloat = 30
    var width: CGFloat = 720
}

@MainActor
private struct ChangingSection: View {
    let state: ChangingCards
    var body: some View {
        QuantizedCardGrid(minimumCellWidth: 320) {
            ForEach(0..<state.count, id: \.self) { index in
                TelemetryCard(title: "\(index)", plate: "", value: "45%", gaugeValue: nil) {
                    Color.clear.frame(height: index == state.count - 1 ? state.contentHeight : 30)
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CardFrames.self,
                                           value: ["\(index)": proxy.frame(in: .named("section"))])
                })
            }
        }
        .frame(width: state.width, alignment: .topLeading)
    }
}

struct CardGridTests {
    @Test("Preset and answer content remain scrollable in the shortest interpreter panel")
    @MainActor
    func shortInterpreterScrolls() throws {
        let hosting = NSHostingView(rootView: InterpreterPanel().makeView()
            .frame(width: 338, height: 184))
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 338, height: 184),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(hosting)
        let scrolls = scrollViews(in: hosting)
        #expect(scrolls.count >= 2)
        let overflowing = scrolls.filter {
            ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height
        }
        let chooser = try #require(overflowing.first)
        let document = try #require(chooser.documentView)
        let before = chooser.contentView.bounds.origin.y
        chooser.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.maxY - chooser.contentView.bounds.height))
        chooser.reflectScrolledClipView(chooser.contentView)
        #expect(chooser.contentView.bounds.origin.y > before)
    }

    @MainActor
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    @Test("Live content, membership and width changes recompute the common footprint")
    @MainActor
    func liveChanges() throws {
        let state = ChangingCards()
        let measured = FrameCapture()
        let root = ChangingSection(state: state)
            .coordinateSpace(name: "section")
            .onPreferenceChange(CardFrames.self) { measured.frames = $0 }
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 720, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(hosting)
        let before = try #require(measured.frames["0"]).height
        state.contentHeight = 210
        state.count = 7
        state.width = 320
        window.setContentSize(CGSize(width: 320, height: 900))
        settle(hosting)
        #expect(measured.frames.count == 7)
        let after = try #require(measured.frames["6"]).height
        #expect(after > before)
        for frame in measured.frames.values {
            #expect(frame.width == 320)
            #expect(frame.height == after)
        }
        state.contentHeight = 30
        state.count = 5
        state.width = 720
        window.setContentSize(CGSize(width: 720, height: 900))
        settle(hosting)
        #expect(measured.frames.count == 5)
        #expect(try #require(measured.frames["0"]).height == before)
    }
    @Test("Peer instruments share the largest footprint across the entire section")
    @MainActor
    func largestCardSetsEveryCell() throws {
        let frames = measure(width: 720)
        let short = try #require(frames["short"])
        let tall = try #require(frames["tall"])
        let last = try #require(frames["last"])
        #expect(short.width == tall.width)
        #expect(short.height == tall.height)
        #expect(last.height == tall.height)
        #expect(short.minY == tall.minY)
        #expect(last.minY >= tall.maxY + 13)
        #expect(tall.height.truncatingRemainder(dividingBy: 8) == 0)
    }

    @Test("Optional GPU and battery peers keep equal cells at every dashboard width",
          arguments: [5, 6, 7])
    @MainActor
    func optionalInstruments(count: Int) throws {
        for width: CGFloat in [320, 720, 1_010] {
            let root = QuantizedCardGrid(minimumCellWidth: 320) {
                ForEach(0..<count, id: \.self) { index in
                    instrument("\(index)", height: index == count - 1 ? 210 : 30)
                }
            }
            let frames = capture(root, width: width)
            let largest = try #require(frames["\(count - 1)"])
            #expect(frames.count == count)
            for frame in frames.values {
                #expect(frame.size == largest.size)
                #expect(frame.minX >= 0)
                #expect(frame.maxX <= width)
                #expect(frame.height >= 236) // Largest 210-point content plus card insets.
            }
            let ordered = (0..<count).compactMap { frames["\($0)"] }
            for (index, frame) in ordered.enumerated() {
                for other in ordered.dropFirst(index + 1) {
                    #expect(!frame.intersects(other))
                }
            }
        }
    }

    @Test("Compact badges take the largest intrinsic width and retain their contents")
    @MainActor
    func compactArtifacts() throws {
        let names = ["uv", "python3", "wrench-and-screwdriver"]
        let root = QuantizedCardGrid(usesLargestIntrinsicWidth: true,
                                     horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(names, id: \.self) { name in
                ConsoleBadge(text: name, fillsCell: true)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: CardFrames.self,
                                               value: [name: proxy.frame(in: .named("section"))])
                    })
            }
        }
        let frames = capture(root, width: 460)
        let largest = try #require(frames[names.last!])
        #expect(frames.count == 3)
        #expect(largest.width.truncatingRemainder(dividingBy: 8) == 0)
        #expect(largest.height.truncatingRemainder(dividingBy: 8) == 0)
        for frame in frames.values { #expect(frame.size == largest.size) }
    }

    @Test("An empty peer section has no phantom height")
    @MainActor
    func emptySection() throws {
        let root = QuantizedCardGrid { EmptyView() }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardFrames.self,
                                       value: ["empty": proxy.frame(in: .named("section"))])
            })
        let frames = capture(root, width: 460)
        #expect(try #require(frames["empty"]).height == 0)
    }

    @Test("High core counts stay inside a narrow dashboard card", arguments: [false, true])
    @MainActor
    func highCoreCount(clustered: Bool) throws {
        let topology = clustered
            ? CPUTopology(logicalCores: 128, efficiencyCores: 4, performanceCores: 124,
                          efficiencyRange: 0..<4, performanceRange: 4..<128)
            : CPUTopology(logicalCores: 128)
        let root = CoreGrid(values: Array(repeating: 0.45, count: 128),
                            topology: topology)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardFrames.self,
                                       value: ["cores": proxy.frame(in: .named("section"))])
            })
        let frame = try #require(capture(root, width: 320)["cores"])
        #expect(frame.minX >= 0)
        #expect(frame.maxX <= 320)
    }

    @MainActor
    private func measure(width: CGFloat) -> [String: CGRect] {
        let root = QuantizedCardGrid(minimumCellWidth: 320) {
            instrument("short", height: 30)
            instrument("tall", height: 210)
            instrument("last", height: 60)
        }
        return capture(root, width: width)
    }

    @MainActor
    private func capture<Content: View>(_ content: Content, width: CGFloat) -> [String: CGRect] {
        let capture = FrameCapture()
        let root = content.frame(width: width, alignment: .topLeading)
        .coordinateSpace(name: "section")
        .onPreferenceChange(CardFrames.self) { capture.frames = $0 }
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(hosting)
        return capture.frames
    }

    @MainActor
    private func settle<Content: View>(_ hosting: NSHostingView<Content>) {
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    private func instrument(_ name: String, height: CGFloat) -> some View {
        TelemetryCard(title: name, plate: name, value: "45%", gaugeValue: nil, subtitle: "Live reading") {
            Color.clear.frame(height: height)
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CardFrames.self,
                                   value: [name: proxy.frame(in: .named("section"))])
        })
    }
}
