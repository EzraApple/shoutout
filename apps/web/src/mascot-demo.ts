import { createMessageLoop } from "./message-loop";
import { sampleIndicatorBarWidths } from "./indicator-waveform";
import { indicatorMotion, indicatorTimeline } from "./indicator-timeline";

const frameURL = (name: string) => `/assets/mascot/wall/${name}.png`;
const frameNames = [
  ...Array.from({ length: 4 }, (_, index) => `idle-${index + 1}`),
  ...Array.from({ length: indicatorMotion.microphoneFrameCount }, (_, index) => `recording-intro-${index + 1}`),
  "recording-hold",
];

export function setupMascotDemos() {
  const roots = document.querySelectorAll<HTMLElement>("[data-mascot-demo]");
  if (!roots.length) return;
  const framesReady = Promise.all(frameNames.map(async (name) => {
    const image = new Image();
    image.src = frameURL(name);
    await image.decode();
  }));
  roots.forEach((root) => setupDemo(root, framesReady));
}

function setupDemo(root: HTMLElement, framesReady: Promise<unknown>) {
  const crab = root.querySelector<HTMLElement>(".demo-crab")!;
  const image = root.querySelector<HTMLImageElement>("[data-crab-frame]")!;
  const viewport = root.matches("[data-demo-viewport]")
    ? root : root.querySelector<HTMLElement>("[data-demo-viewport]")!;
  const bars = root.querySelectorAll<HTMLElement>("[data-level-bar]");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const messageLoop = root.hasAttribute("data-message-loop") ? createMessageLoop(root) : null;
  const stationaryCrab = root.hasAttribute("data-demo-stationary");
  let indicatorElapsed = 0;
  let ready = false;
  let visible = false;
  let frameRequest = 0;
  let previousTime = 0;
  let offset = 0;
  let travel = 72;
  let direction = 1;
  let steps = 0;
  let walkDelay = 0;
  let idleFrame = 1;
  let currentFrame = "idle-1";

  function setFrame(name: string) {
    if (name === currentFrame) return;
    currentFrame = name;
    image.src = frameURL(name);
  }

  function setPhase(phase: string) {
    if (root.dataset.demoPhase !== phase) root.dataset.demoPhase = phase;
  }

  function renderPlayback(time: number) {
    if (time < indicatorTimeline.microphoneOpenEnd) {
      setPhase("intro");
      const frame = Math.floor(time / indicatorMotion.microphoneOpenFrame) + 1;
      setFrame(`recording-intro-${frame}`);
    } else if (time < indicatorTimeline.recordingEnd) {
      setPhase("listening");
      setFrame("recording-hold");
    } else if (time < indicatorTimeline.microphoneCloseEnd) {
      setPhase("outro");
      const elapsed = time - indicatorTimeline.recordingEnd;
      const frame = indicatorMotion.microphoneFrameCount - Math.floor(elapsed / indicatorMotion.microphoneCloseFrame);
      setFrame(`recording-intro-${frame}`);
    } else if (time < indicatorTimeline.processingEnd) {
      setFrame("idle-1");
      setPhase("processing");
    } else if (time < indicatorTimeline.completeEnd) {
      setPhase("done");
    } else {
      setPhase("closing");
    }
    if (time < indicatorTimeline.recordingEnd && bars.length) {
      const widths = sampleIndicatorBarWidths(time);
      bars.forEach((bar, index) => {
        bar.style.transform = `scaleX(${widths[index % widths.length] / 18})`;
      });
    }
  }

  function walkCrab(delta: number) {
    walkDelay -= delta;
    if (walkDelay <= 0) {
      offset += direction * 4;
      if (Math.abs(offset) >= travel) {
        offset = Math.max(-travel, Math.min(travel, offset));
        direction *= -1;
      }
      idleFrame = idleFrame % 4 + 1;
      setFrame(`idle-${idleFrame}`);
      crab.style.setProperty("--crab-offset", `${offset}px`);
      walkDelay = ++steps % 10 === 0 ? 700 : 130;
    }
  }

  function advancePlayback(delta: number): number | null {
    if (messageLoop) return messageLoop.advance(delta);
    indicatorElapsed = (indicatorElapsed + delta) % indicatorTimeline.cycleEnd;
    return indicatorElapsed < indicatorTimeline.closingEnd ? indicatorElapsed : null;
  }

  function tick(time: number) {
    frameRequest = 0;
    const delta = previousTime ? Math.min(time - previousTime, 100) : 0;
    previousTime = time;
    const recordingTime = advancePlayback(delta);
    if (recordingTime !== null) {
      renderPlayback(recordingTime);
    } else {
      setPhase("walking");
      if (stationaryCrab) setFrame("idle-1");
      else walkCrab(delta);
    }
    schedule();
  }

  function schedule() {
    const running = ready && visible && !document.hidden && !reducedMotion.matches;
    root.dataset.demoRunning = String(running);
    if (running) {
      if (!frameRequest) frameRequest = requestAnimationFrame(tick);
    } else {
      cancelAnimationFrame(frameRequest);
      frameRequest = 0;
      previousTime = 0;
    }
  }

  framesReady.then(() => {
    ready = true;
    schedule();
  }).catch(() => {
    messageLoop?.reset(true);
  });
  function syncMotionPreference() {
    indicatorElapsed = 0;
    messageLoop?.reset(reducedMotion.matches);
    setPhase("walking");
    if (reducedMotion.matches) {
      offset = 0;
      crab.style.setProperty("--crab-offset", "0px");
      setFrame("idle-1");
    }
    schedule();
  }
  new ResizeObserver(([entry]) => {
    if (stationaryCrab) return;
    travel = Math.min(72, Math.max(0, (entry.contentRect.height - crab.offsetHeight) / 2 - 16));
    offset = Math.max(-travel, Math.min(travel, offset));
    crab.style.setProperty("--crab-offset", `${offset}px`);
  }).observe(viewport);
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    schedule();
  }).observe(root);
  document.addEventListener("visibilitychange", schedule);
  reducedMotion.addEventListener("change", syncMotionPreference);
  syncMotionPreference();
}
