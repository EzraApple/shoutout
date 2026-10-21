// Matches ClassicWaveform.swift and the 50 ms speech trace in ClassicOverlayPreview.swift.
const speechLevels = [
  0, 0, 0.04, 0.12, 0.25, 0.18, 0.08, 0.02, 0.15, 0.28, 0.11, 0.04, 0,
  0, 0, 0, 0, 0, 0.03, 0.18, 0.09, 0.22, 0.12, 0.05, 0, 0,
];
const weights = [0.50, 0.75, 0.90, 1, 0.90, 0.75, 0.50];
const segments: { time: number; initialLevel: number; targetLevel: number }[] = [];

for (let index = 0; index < 54; index++) {
  const time = index * 0.05;
  const rawLevel = speechLevels[index % speechLevels.length];
  const normalized = Math.min(1, Math.max(0, (rawLevel - 0.006) / (0.30 - 0.006)));
  segments.push({ time, initialLevel: sampleLevel(time), targetLevel: Math.pow(normalized, 0.88) });
}

function sampleLevel(time: number): number {
  for (let index = segments.length - 1; index >= 0; index--) {
    const segment = segments[index];
    if (segment.time > time) continue;
    const duration = segment.targetLevel > segment.initialLevel ? 0.025 : 0.10;
    return segment.targetLevel + (segment.initialLevel - segment.targetLevel)
      * Math.exp(-Math.max(0, time - segment.time) / duration);
  }
  return 0;
}

export function sampleIndicatorBarWidths(timeMs: number): number[] {
  const time = timeMs / 1000;
  return weights.map((weight, index) => {
    const delay = Math.abs(index - 3) * 0.03;
    const level = sampleLevel(time - delay);
    const restingWidth = 3 + (Math.sin(time * 5.2 + index * 1.1) + 1) * 0.7;
    return restingWidth + (18 - restingWidth) * weight * level;
  });
}
