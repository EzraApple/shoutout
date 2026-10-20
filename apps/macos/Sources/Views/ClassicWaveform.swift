import Foundation

struct ClassicWaveform {
    private struct Segment {
        let time: TimeInterval
        let initialLevel: Double
        let targetLevel: Double

        func sampleLevel(at time: TimeInterval) -> Double {
            let duration = targetLevel > initialLevel ? 0.025 : 0.10
            let elapsed = max(0, time - self.time)
            return targetLevel + (initialLevel - targetLevel) * exp(-elapsed / duration)
        }
    }

    private var segments: [Segment] = []

    mutating func recordLevel(_ rawLevel: Float, at time: TimeInterval) {
        guard time.isFinite, time >= (segments.last?.time ?? time) else { return }
        let clampedLevel = rawLevel.isFinite ? min(max(Double(rawLevel), 0), 1) : 0
        let normalized = min(max((clampedLevel - 0.006) / (0.30 - 0.006), 0), 1)
        let targetLevel = pow(normalized, 0.88)
        let initialLevel = sampleLevel(at: time)
        segments.append(Segment(time: time, initialLevel: initialLevel, targetLevel: targetLevel))
        if segments.count > 32 {
            segments.removeFirst(segments.count - 32)
        }
    }

    func sampleLevel(at time: TimeInterval) -> Double {
        guard time.isFinite,
            let segment = segments.last(where: { $0.time <= time })
        else { return 0 }
        return segment.sampleLevel(at: time)
    }

    func sampleBarWidths(at time: TimeInterval) -> [CGFloat] {
        let weights = [0.50, 0.75, 0.90, 1.0, 0.90, 0.75, 0.50]
        guard time.isFinite else { return Array(repeating: 2.5, count: weights.count) }
        return weights.enumerated().map { index, weight in
            let delay = Double(abs(index - weights.count / 2)) * 0.03
            let level = sampleLevel(at: time - delay)
            let restingWidth = 3 + (sin(time * 5.2 + Double(index) * 1.1) + 1) * 0.7
            return restingWidth + (18 - restingWidth) * weight * level
        }
    }
}
