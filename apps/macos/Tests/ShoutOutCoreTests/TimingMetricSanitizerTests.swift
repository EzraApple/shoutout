import Testing
@testable import ShoutOutCore

struct TimingMetricSanitizerTests {
    @Test func millisecondsUsesWholeMilliseconds() {
        #expect(TimingMetricSanitizer.milliseconds(from: 1.2349) == 1234)
    }

    @Test func millisecondsRejectsNonFiniteInputs() {
        #expect(TimingMetricSanitizer.milliseconds(from: .nan) == nil)
        #expect(TimingMetricSanitizer.milliseconds(from: .infinity) == nil)
    }

    @Test func millisecondsRejectsOverflowAfterScaling() {
        #expect(TimingMetricSanitizer.milliseconds(from: Double.greatestFiniteMagnitude) == nil)
    }

    @Test func millisecondsBetweenRejectsReversedOrOverflowingDeltas() {
        #expect(TimingMetricSanitizer.milliseconds(between: 2, and: 1) == nil)
        #expect(
            TimingMetricSanitizer.milliseconds(
                between: -Double.greatestFiniteMagnitude,
                and: Double.greatestFiniteMagnitude
            ) == nil
        )
    }

    @Test func finiteNonNegativeDropsValuesThatCannotBePersistedAsJSON() {
        #expect(TimingMetricSanitizer.finiteNonNegative(2.5) == 2.5)
        #expect(TimingMetricSanitizer.finiteNonNegative(-1) == nil)
        #expect(TimingMetricSanitizer.finiteNonNegative(.nan) == nil)
        #expect(TimingMetricSanitizer.finiteNonNegative(.infinity) == nil)
    }
}
