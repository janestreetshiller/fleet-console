import SwiftUI
import Charts

// Live telemetry, drawn with Swift Charts.
//
// The popover keeps the hand-rolled `Sparkline` (14pt tall, no axes by design).
// The window's charts are a different instrument: current values rendered as
// monospaced-digit text beside the plot rather than as axis clutter, gradient
// area fills for the "wave", and a y scale chosen per *kind* of series rather
// than one rule for both. A chart here shows shape and trend; the exact number
// sits next to it. Both are honest: a rate with no second sample draws an empty
// track, never a confident flat line.
//
// Why the scales differ, since this is the interesting decision:
//
//   * A **bounded** series (utilisation, memory share — anything 0…1) gets a
//     *linear* axis over an auto-ranged window. Not a log axis: log compresses
//     the top of a bounded range, so 50→100% becomes 1.70→2.00 and a machine
//     spiking off a 50% floor looks flatter than it did before. What you
//     actually want above a high baseline is resolution, and the honest way to
//     get resolution is to move the window and then *say where the window is*.
//   * An **unbounded** series (byte rates) gets a *log* axis, because it really
//     does span decades and spends most of its life near zero.
//
// Both rules have the same guard: a chart too short to carry its axis labels
// keeps its plain domain. A rescaled axis you cannot read is the failure this
// change exists to avoid.

/// One sample in a telemetry series. Index-based: histories are ring buffers,
/// so the x position is the sample's age, not a wall-clock time.
private struct Trace: Identifiable {
    let id: Int
    let value: Double
}

private func traces(of values: [Double]) -> [Trace] {
    values.enumerated().map { Trace(id: $0.offset, value: $0.element) }
}

// MARK: - Bounded window

/// The y window for a bounded 0…1 series, and whether it is narrower than the
/// full range — which is the same question as "must this chart label itself".
private struct BoundedWindow {
    let lower: Double
    let upper: Double
    let zoomed: Bool

    /// The floor on how far the window may close. A flat series has to stay
    /// flat: without this, idle jitter of two points fills the plot and the
    /// chart cries wolf every two seconds. 0.15 is picked against the 2 s
    /// cadence — idle CPU wobble of 2–5 points lands at a fifth of the plot
    /// height, which is visible without being an event.
    static let minimumSpan: Double = 0.15
    /// Headroom above and below the observed band, as a share of the span.
    /// Keeps the trace — and Catmull-Rom's overshoot between samples — off the
    /// plot boundary.
    private static let headroom: Double = 0.10

    init(_ values: [Double], autoRange: Bool) {
        let clamped = values.map { min(1, max(0, $0)) }
        guard autoRange, let low = clamped.min(), let high = clamped.max() else {
            lower = 0
            upper = 1
            zoomed = false
            return
        }

        var bottom = low
        var top = high
        let observed = top - bottom
        if observed < Self.minimumSpan {
            let grow = (Self.minimumSpan - observed) / 2
            bottom -= grow
            top += grow
        }
        let pad = (top - bottom) * Self.headroom
        bottom = max(0, bottom - pad)
        top = min(1, top + pad)
        // Clamping at 0 or 1 can eat the span back; re-grow off the other end
        // rather than shipping a window narrower than the floor.
        if top - bottom < Self.minimumSpan {
            if bottom <= 0 {
                top = min(1, Self.minimumSpan)
            } else {
                bottom = max(0, top - Self.minimumSpan)
            }
        }

        lower = bottom
        upper = top
        // A hair inside 0 and 1 still counts as the full range: labelling
        // "0%–100%" on a chart that is showing 0…1 is furniture, not honesty.
        zoomed = bottom > 0.005 || top < 0.995
    }
}

// MARK: - Load wave

/// CPU / GPU / memory utilisation as a filled wave over the last two minutes.
///
/// The y window tracks the observed band rather than sitting fixed at 0…1, so
/// the volatility on top of a high baseline is the thing you see — and the two
/// axis labels state the window, because a trace that fills the plot must never
/// be mistakable for a machine at 100%.
struct LoadWaveChart: View {
    let values: [Double]
    var tint: Color = .accentColor
    var height: CGFloat = ConsoleMetrics.chartHeight

    private var labelsFit: Bool { height >= ConsoleMetrics.chartAxisMinHeight }

    var body: some View {
        let window = BoundedWindow(values, autoRange: labelsFit)
        return Chart(traces(of: values)) { trace in
            AreaMark(x: .value("Sample", trace.id),
                     yStart: .value("Base", window.lower),
                     yEnd: .value("Load", min(1, max(0, trace.value))))
                .foregroundStyle(.linearGradient(
                    colors: [tint.opacity(0.32), tint.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Sample", trace.id),
                     y: .value("Load", min(1, max(0, trace.value))))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: ConsoleMetrics.chartStroke))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            // Two marks, the window's own bounds, and nothing else: no ticks,
            // no domain line, hairline gridlines. The axis is here to state the
            // range, not to let you read values off the plot — that is what the
            // live numeral in the card header is for.
            AxisMarks(values: window.zoomed ? [window.lower, window.upper] : []) { mark in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(ConsoleColor.hairline)
                AxisValueLabel {
                    Text(ConsoleFmt.utilPercent(mark.as(Double.self)))
                        .font(ConsoleFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(SurfaceInk.secondary)
                }
            }
        }
        .chartYScale(domain: window.lower...window.upper)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.padding(ConsoleMetrics.chartPlotInset)
                .padding(.trailing, window.zoomed ? ConsoleMetrics.chartAxisGutter
                                                 : ConsoleMetrics.chartPlotInset)
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityLabel(window))
    }

    private func accessibilityLabel(_ window: BoundedWindow) -> String {
        let base = "Load history, \(values.count) samples, "
            + "current \(ConsoleFmt.utilPercent(values.last))"
        guard window.zoomed else { return base }
        return base + ", axis \(ConsoleFmt.utilPercent(window.lower)) to "
            + ConsoleFmt.utilPercent(window.upper)
    }
}

// MARK: - Throughput

/// Disk read/write bandwidth, two series on one shared scale.
///
/// Log, when there is room to label it. Byte rates are the genuinely unbounded
/// series in the app: on a linear axis a 40 KB/s log write and a 900 MB/s file
/// copy share the bottom pixel row, which is four decades of difference thrown
/// away. Zero is a real sample — an idle disk — and log(0) is not a number, so
/// samples are lifted to the axis floor instead of being dropped. The trace
/// rests on the bottom gridline, and that gridline is labelled with the floor.
struct ThroughputChart: View {
    let read: [Double]
    let write: [Double]
    var height: CGFloat = ConsoleMetrics.chartHeight
    var readLabel: String = TelemetrySeries.read.label
    var writeLabel: String = TelemetrySeries.write.label
    var metric = "Disk"

    /// Axis floor. Below a kilobyte per second there is nothing to tell apart,
    /// and `ConsoleFmt.byteRate` already floors its text at the same place.
    private static let floorRate: Double = 1024
    /// The axis never closes in tighter than this, so an idle disk's 12 KB/s
    /// housekeeping cannot become a full-height event.
    private static let minimumCeiling: Double = 1_048_576

    private var labelsFit: Bool { height >= ConsoleMetrics.chartAxisMinHeight }

    private var peak: Double {
        max(read.max() ?? 0, write.max() ?? 0, Self.minimumCeiling)
    }

    /// Log above the floor when labelled; the previous linear-with-a-floor
    /// scale when not, because an unlabelled log axis makes a 4 KB/s blip look
    /// like a write storm.
    private var ceiling: Double { labelsFit ? peak * 1.25 : peak }

    /// Three labels at most: the floor, the geometric middle (the midpoint of a
    /// log axis is its geometric mean, not its arithmetic one) and the top.
    private var axisValues: [Double] {
        guard labelsFit else { return [] }
        return [Self.floorRate, (Self.floorRate * ceiling).squareRoot(), ceiling]
    }

    var body: some View {
        chart
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: axisValues) { mark in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(ConsoleColor.hairline)
                    AxisValueLabel {
                        Text(ConsoleFmt.byteRate(mark.as(Double.self)))
                            .font(ConsoleFont.caption)
                            .monospacedDigit()
                            .foregroundStyle(SurfaceInk.secondary)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.padding(ConsoleMetrics.chartPlotInset)
                    .padding(.trailing, labelsFit ? ConsoleMetrics.chartAxisGutter
                                                  : ConsoleMetrics.chartPlotInset)
            }
            .frame(height: height)
            .accessibilityLabel("\(metric) throughput, \(readLabel) \(ConsoleFmt.byteRate(read.last)), "
                                + "\(writeLabel) \(ConsoleFmt.byteRate(write.last))"
                                + (labelsFit ? ", logarithmic axis" : ""))
    }

    /// Split out so the scale type can differ without duplicating the marks.
    @ViewBuilder
    private var chart: some View {
        if labelsFit {
            marks.chartYScale(domain: Self.floorRate...ceiling, type: .log)
        } else {
            marks.chartYScale(domain: 0...ceiling)
        }
    }

    private var marks: some View {
        Chart {
            ForEach(traces(of: read)) { trace in
                LineMark(x: .value("Sample", trace.id),
                         y: .value("Bytes", plotted(trace.value)),
                         series: .value("Direction", readLabel))
                    .foregroundStyle(TelemetrySeries.read.color)
                    .lineStyle(StrokeStyle(lineWidth: ConsoleMetrics.chartStroke))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(traces(of: write)) { trace in
                LineMark(x: .value("Sample", trace.id),
                         y: .value("Bytes", plotted(trace.value)),
                         series: .value("Direction", writeLabel))
                    .foregroundStyle(TelemetrySeries.write.color)
                    .lineStyle(StrokeStyle(lineWidth: ConsoleMetrics.chartStroke))
                    .interpolationMethod(.catmullRom)
            }
        }
    }

    /// Lifts a sample onto the axis. On the log scale this is what keeps an
    /// idle disk on the bottom gridline instead of producing a broken path.
    private func plotted(_ value: Double) -> Double {
        labelsFit ? max(Self.floorRate, min(value, ceiling)) : max(0, min(value, ceiling))
    }
}

// MARK: - Chart card

/// An instrument: one metric's dial, its history, and the facts underneath.
///
/// This used to be a title row carrying the live numeral, over a full-width
/// trace. Four of them stacked meant four cards of roughly 200–260pt for four
/// numbers — one screenful of scroll per metric on a window whose content column
/// was already sharing its width with a sidebar and an inspector, and a header
/// numeral that told you 77% without telling you whether 77% was anywhere near
/// the top of the range.
///
/// The dial answers that in the same space the numeral occupied, so the header
/// loses the number rather than gaining a gauge — and the card is laid out
/// horizontally, gauge beside trace, which is what lets two of them sit side by
/// side in the grid instead of stacking.
struct TelemetryCard<Content: View>: View {
    let title: String
    /// The plotted legend struck into this plate's top border — "01 · CPU".
    /// Given at the call site rather than derived from `title`, because the
    /// number is the card's position in the module's grid and the grid is the
    /// caller's. A card that numbered itself would be a card that renumbered
    /// itself when the GPU withheld its key and the module dropped to three.
    let plate: String
    var tone: StatusTone = .neutral
    /// The formatted current value, shown on the dial's face.
    let value: String
    /// 0…1 for the needle. Nil parks it: the metric has not been sampled.
    var gaugeValue: Double?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(ConsoleFont.cardTitle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(value)
                    .font(ConsoleFont.metricValue)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityLabel("\(title): \(value)")
            }
            if let subtitle {
                Text(subtitle)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .elevatedCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Chart legend dot

struct LegendDot: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Swatch(color: color)
            Text(label)
                .font(ConsoleFont.caption)
                .foregroundStyle(.secondary)
            // A rate is one token. In the wider card this never came up; in a grid
            // cell "5.3 MB/s" broke after the numeral and the legend became two
            // lines tall, which then set the height of every card in its row.
            Text(value)
                .font(ConsoleFont.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(ConsoleColor.numeral)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
    }
}
