import SwiftUI
import Charts
import FleetCore

private struct Trace: Identifiable {
    let id: Int
    let time: Double
    let value: Double
}

private func traces(of values: [Double], times: [Date], range: ClosedRange<Date>?) -> [Trace] {
    let timed = !times.isEmpty && times.count == values.count
    return values.enumerated().compactMap { index, value in
        if timed, let range, !range.contains(times[index]) { return nil }
        return Trace(id: index, time: timed ? times[index].timeIntervalSince1970 : Double(index), value: value)
    }
}

private struct TimelineAxis: ViewModifier {
    let times: [Date]
    let count: Int
    let range: ClosedRange<Date>?
    @ViewBuilder func body(content: Content) -> some View {
        if !times.isEmpty, times.count == count, let range {
            let middle = range.lowerBound.addingTimeInterval(range.upperBound.timeIntervalSince(range.lowerBound) / 2)
            content
                .chartXScale(domain: range)
                .chartXAxis {
                    AxisMarks(values: [range.lowerBound, middle, range.upperBound]) { mark in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ConsoleColor.hairline)
                        AxisValueLabel(anchor: mark.index == 0 ? .leading : mark.index == mark.count - 1 ? .trailing : .center) {
                            if let date = mark.as(Date.self) {
                                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                                    .font(ConsoleFont.caption).monospacedDigit()
                            }
                        }
                    }
                }
        } else {
            content.chartXScale(domain: 0...Double(max(1, count - 1))).chartXAxis(.hidden)
        }
    }
}

private struct BoundedWindow {
    let lower: Double
    let upper: Double
    let zoomed: Bool

    static let minimumSpan: Double = 0.15
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
        if top - bottom < Self.minimumSpan {
            if bottom <= 0 {
                top = min(1, Self.minimumSpan)
            } else {
                bottom = max(0, top - Self.minimumSpan)
            }
        }

        lower = bottom
        upper = top
        zoomed = bottom > 0.005 || top < 0.995
    }
}

struct LoadWaveChart: View {
    let values: [Double]
    var times: [Date] = []
    var range: ClosedRange<Date>?
    var tint: Color = .accentColor
    var height: CGFloat = ConsoleMetrics.chartHeight

    var metric: String = "Load"

    private var labelsFit: Bool { height >= ConsoleMetrics.chartAxisMinHeight }

    var body: some View {
        let points = traces(of: values, times: times, range: range)
        let window = BoundedWindow(points.map(\.value), autoRange: labelsFit)
        return Chart(points) { trace in
            if !times.isEmpty && times.count == values.count {
                loadMarks(trace, x: .value("Time", Date(timeIntervalSince1970: trace.time)), window: window)
            } else {
                loadMarks(trace, x: .value("Sample", trace.id), window: window)
            }
        }
        .modifier(TimelineAxis(times: times, count: values.count, range: range))
        .chartYAxis {
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

    @ChartContentBuilder
    private func loadMarks<X: Plottable>(_ trace: Trace, x: PlottableValue<X>, window: BoundedWindow) -> some ChartContent {
        AreaMark(x: x, yStart: .value("Base", window.lower), yEnd: .value("Load", min(1, max(0, trace.value))))
            .foregroundStyle(.linearGradient(colors: [tint.opacity(0.32), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.linear)
            .accessibilityHidden(true)
        LineMark(x: x, y: .value("Load", min(1, max(0, trace.value))))
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: ConsoleMetrics.chartStroke))
            .interpolationMethod(.linear)
            .accessibilityLabel(metric)
            .accessibilityValue(ConsoleFmt.utilPercent(trace.value))
    }

    private func accessibilityLabel(_ window: BoundedWindow) -> String {
        let base = "\(metric) history, \(traces(of: values, times: times, range: range).count) visible samples, "
            + "current \(ConsoleFmt.utilPercent(values.last))"
        let timeDescription = range.map { ", \(Int($0.upperBound.timeIntervalSince($0.lowerBound))) seconds displayed" } ?? ""
        guard window.zoomed else { return base + timeDescription }
        return base + timeDescription + ", axis \(ConsoleFmt.utilPercent(window.lower)) to "
            + ConsoleFmt.utilPercent(window.upper)
    }
}

struct ThroughputChart: View {
    let read: [Double]
    let write: [Double]
    var times: [Date] = []
    var range: ClosedRange<Date>?
    var height: CGFloat = ConsoleMetrics.chartHeight
    var readLabel: String = TelemetrySeries.read.label
    var writeLabel: String = TelemetrySeries.write.label
    var metric = "Disk"

    private static let floorRate: Double = 1024
    private static let minimumCeiling: Double = 1_048_576

    private var labelsFit: Bool { height >= ConsoleMetrics.chartAxisMinHeight }

    private var peak: Double {
        max(traces(of: read, times: times, range: range).map(\.value).max() ?? 0,
            traces(of: write, times: times, range: range).map(\.value).max() ?? 0, Self.minimumCeiling)
    }

    private var ceiling: Double { labelsFit ? peak * 1.25 : peak }

    private var axisValues: [Double] {
        guard labelsFit else { return [] }
        return [Self.floorRate, (Self.floorRate * ceiling).squareRoot(), ceiling]
    }

    var body: some View {
        chart
            .modifier(TimelineAxis(times: seriesTimes, count: read.count, range: range))
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

    @ViewBuilder
    private var chart: some View {
        if labelsFit {
            marks.chartYScale(domain: Self.floorRate...ceiling, type: .log)
        } else {
            marks.chartYScale(domain: 0...ceiling)
        }
    }

    private var seriesTimes: [Date] { times.count == read.count && times.count == write.count ? times : [] }

    private var marks: some View {
        Chart {
            ForEach(traces(of: read, times: seriesTimes, range: range)) { trace in
                if !seriesTimes.isEmpty {
                    line(trace, x: .value("Time", Date(timeIntervalSince1970: trace.time)), label: readLabel, color: TelemetrySeries.read.color)
                } else {
                    line(trace, x: .value("Sample", trace.id), label: readLabel, color: TelemetrySeries.read.color)
                }
            }
            ForEach(traces(of: write, times: seriesTimes, range: range)) { trace in
                if !seriesTimes.isEmpty {
                    line(trace, x: .value("Time", Date(timeIntervalSince1970: trace.time)), label: writeLabel, color: TelemetrySeries.write.color)
                } else {
                    line(trace, x: .value("Sample", trace.id), label: writeLabel, color: TelemetrySeries.write.color)
                }
            }
        }
    }

    private func line<X: Plottable>(_ trace: Trace, x: PlottableValue<X>, label: String, color: Color) -> some ChartContent {
        LineMark(x: x, y: .value("Bytes", plotted(trace.value)), series: .value("Direction", label))
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: ConsoleMetrics.chartStroke))
            .interpolationMethod(.linear)
            .accessibilityLabel("\(metric) \(label)")
            .accessibilityValue(ConsoleFmt.byteRate(trace.value))
    }

    private func plotted(_ value: Double) -> Double {
        labelsFit ? max(Self.floorRate, min(value, ceiling)) : max(0, min(value, ceiling))
    }
}

struct TelemetryCard<Content: View>: View {
    let title: String
    let plate: String
    var tone: StatusTone = .neutral
    let value: String
    var gaugeValue: Double?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(ConsoleFont.cardTitle)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("telemetry.\(title).title")
                Spacer(minLength: 8)
                Text(value)
                    .font(ConsoleFont.metricValue)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityLabel("\(title): \(value)")
                    .accessibilityIdentifier("telemetry.\(title).value")
            }
            if let subtitle {
                Text(subtitle)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: 142, maxHeight: .infinity, alignment: .topLeading)
        .elevatedCard()
        .accessibilityElement(children: .contain)
    }
}

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
            Text(value)
                .font(ConsoleFont.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(ConsoleColor.numeral)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
