import { createMessageLoop } from "./message-loop";
import { sampleIndicatorBarWidths } from "./indicator-waveform";

const frameURL = (name: string) => `/assets/mascot/wall/${name}.png`;
const frameNames = [
  ...Array.from({ length: 4 }, (_, index) => `idle-${index + 1}`),
  ...Array.from({ length: 6 }, (_, index) => `recording-intro-${index + 1}`),
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
  const messageLoop = createMessageLoop(root);
  const stationaryCrab = root.hasAttribute("data-demo-stationary");
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
    if (time < 408) {
      setPhase("intro");
      setFrame(`recording-intro-${Math.min(6, Math.floor(time / 68) + 1)}`);
    } else if (time < 2608) {
      setPhase("listening");
      setFrame("recording-hold");
    } else if (time < 2884) {
      setPhase("outro");
      setFrame(`recording-intro-${Math.max(1, 6 - Math.floor((time - 2608) / 46))}`);
    } else if (time < 3884) {
      setFrame("idle-1");
      setPhase("processing");
    } else {
      setPhase("done");
    }
    if (time < 2608 && bars.length) {
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

  function tick(time: number) {
    frameRequest = 0;
    const delta = previousTime ? Math.min(time - previousTime, 100) : 0;
    previousTime = time;
    const recordingTime = messageLoop.advance(delta);
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
    messageLoop.reset(true);
  });
  function syncMotionPreference() {
    messageLoop.reset(reducedMotion.matches);
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
