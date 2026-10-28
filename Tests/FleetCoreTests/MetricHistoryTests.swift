import Foundation
import Testing
import FleetCore

struct MetricHistoryTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test("Sampling gaps keep their actual duration and peaks survive zoom")
    func irregularSamples() {
        var history = MetricHistory()
        for (offset, value) in [(0.0, 0.1), (2.0, 1.0), (19.0, 0.2), (30.0, 0.3)] {
            history.append(value, at: start.addingTimeInterval(offset))
        }
        #expect(history.samples[2].time.timeIntervalSince(history.samples[1].time) == 17)
        let wide = history.visible(in: ChartTimeWindow.seconds30.range(endingAt: start.addingTimeInterval(30)))
        #expect(wide.map(\.value) == [0.1, 1, 0.2, 0.3])
        let narrow = history.visible(in: ChartTimeWindow.seconds15.range(endingAt: start.addingTimeInterval(30)))
        #expect(narrow.map(\.value) == [0.2, 0.3])
    }

    @Test("Retention, capacity, duplicate timestamps and invalid samples are bounded")
    func boundaries() {
        var history = MetricHistory(retention: 10, capacity: 3)
        for offset in [0.0, 1, 2, 3] { history.append(offset, at: start.addingTimeInterval(offset)) }
        #expect(history.samples.map(\.value) == [1, 2, 3])
        history.append(9, at: start.addingTimeInterval(3))
        history.append(.nan, at: start.addingTimeInterval(4))
        history.append(8, at: start)
        #expect(history.samples.map(\.value) == [1, 2, 9])
        history.append(20, at: start.addingTimeInterval(20))
        #expect(history.samples.map(\.value) == [20])
    }
}
