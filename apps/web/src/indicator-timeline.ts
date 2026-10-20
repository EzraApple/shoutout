// Microphone frames and capsule morphs match FloatingIndicator.swift.
export const indicatorMotion = {
  microphoneFrameCount: 6,
  microphoneOpenFrame: 68,
  microphoneCloseFrame: 46,
  capsuleMorph: 160,
} as const;

const microphoneOpenEnd = indicatorMotion.microphoneFrameCount * indicatorMotion.microphoneOpenFrame;
const recordingEnd = microphoneOpenEnd + 2200;
const microphoneCloseEnd = recordingEnd + indicatorMotion.microphoneFrameCount * indicatorMotion.microphoneCloseFrame;
const processingEnd = microphoneCloseEnd + 1000;
const completeEnd = processingEnd + 500;
const closingEnd = completeEnd + indicatorMotion.capsuleMorph;

export const indicatorTimeline = {
  microphoneOpenEnd,
  recordingEnd,
  microphoneCloseEnd,
  processingEnd,
  completeEnd,
  closingEnd,
  cycleEnd: closingEnd + 2000,
} as const;
