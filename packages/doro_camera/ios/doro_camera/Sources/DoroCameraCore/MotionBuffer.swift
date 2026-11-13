import Foundation

/// A time-bounded buffer of timestamped samples (video frames or audio buffers). Generic so the real
/// engine stores `CMSampleBuffer`s while tests store integers. Timestamps are seconds on one monotonic clock.
public struct TimedRing<Element> {
    public struct Entry {
        public let time: Double
        public let element: Element
    }

    public private(set) var entries: [Entry] = []
    public let windowSeconds: Double

    public init(windowSeconds: Double) {
        precondition(windowSeconds >= 0, "window must not be negative")
        self.windowSeconds = windowSeconds
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    public var oldestTime: Double? { entries.first?.time }
    public var newestTime: Double? { entries.last?.time }

    /// Appends a sample and drops everything older than the window measured from the newest sample.
    /// Out-of-order timestamps are dropped: the capture pipelines deliver monotonically.
    public mutating func append(_ element: Element, at time: Double) {
        if let newest = entries.last, time < newest.time { return }
        entries.append(Entry(time: time, element: element))
        trim()
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Samples with `from <= time <= to`.
    public func samples(from: Double, to: Double) -> [Entry] {
        entries.filter { $0.time >= from && $0.time <= to }
    }

    private mutating func trim() {
        guard let newest = entries.last?.time else { return }
        let cutoff = newest - windowSeconds
        var drop = 0
        while drop < entries.count, entries[drop].time < cutoff { drop += 1 }
        if drop > 0 { entries.removeFirst(drop) }
    }
}

/// Which part of the timeline a Motion Memory clip covers (MOT-002).
public struct MotionClipWindow: Equatable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let shutterTime: Double
    /// Actual pre-roll available, which can be less than requested right after the camera opens.
    public let preRollSeconds: Double
    public let postRollSeconds: Double
    public let includesAudio: Bool

    public var durationSeconds: Double { endTime - startTime }
}

public enum MotionClipPlanner {
    public static let defaultPreRollSeconds = 1.5
    public static let defaultPostRollSeconds = 1.5

    /// Plans the clip around the shutter. The start is clamped to what the ring really holds, so the
    /// clip never claims footage that was not buffered.
    public static func plan(
        shutterTime: Double,
        oldestBufferedTime: Double?,
        preRollSeconds: Double = defaultPreRollSeconds,
        postRollSeconds: Double = defaultPostRollSeconds,
        audio: Bool
    ) -> MotionClipWindow {
        let wantedStart = shutterTime - Swift.max(0, preRollSeconds)
        let start: Double
        if let oldest = oldestBufferedTime {
            start = Swift.min(Swift.max(wantedStart, oldest), shutterTime)
        } else {
            start = shutterTime
        }
        let post = Swift.max(0, postRollSeconds)
        return MotionClipWindow(
            startTime: start,
            endTime: shutterTime + post,
            shutterTime: shutterTime,
            preRollSeconds: shutterTime - start,
            postRollSeconds: post,
            includesAudio: audio
        )
    }

    /// Video and audio are cut with the same window so one container keeps A/V sync (ADR-0005).
    /// Returns, for each stream, the entries inside the window in order.
    public static func select<V, A>(
        window: MotionClipWindow,
        video: TimedRing<V>,
        audio: TimedRing<A>
    ) -> (video: [TimedRing<V>.Entry], audio: [TimedRing<A>.Entry]) {
        (
            video.samples(from: window.startTime, to: window.endTime),
            window.includesAudio ? audio.samples(from: window.startTime, to: window.endTime) : []
        )
    }

    /// Seconds between the first video and first audio sample of a selection. A/V sync tolerance is 40 ms.
    public static func startSkew(videoFirst: Double?, audioFirst: Double?) -> Double? {
        guard let v = videoFirst, let a = audioFirst else { return nil }
        return a - v
    }

    public static let avSyncToleranceSeconds = 0.040
}
