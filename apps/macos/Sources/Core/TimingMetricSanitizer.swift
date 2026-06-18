import Foundation

public enum TimingMetricSanitizer {
    public static func milliseconds(from seconds: Double?) -> Int? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }

        let milliseconds = seconds * 1000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < Double(Int.max) else {
            return nil
        }

        return Int(milliseconds)
    }

    public static func milliseconds(between start: Double?, and end: Double?) -> Int? {
        guard let start, let end, start.isFinite, end.isFinite, end >= start else {
            return nil
        }

        return milliseconds(from: end - start)
    }

    public static func finiteNonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
