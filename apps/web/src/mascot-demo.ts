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
  const play = root.querySelector<HTMLButtonElement>("[data-demo-play]")!;
  const pause = root.querySelector<HTMLButtonElement>("[data-demo-pause]")!;
  const status = root.querySelector<HTMLElement>("[data-demo-status]")!;
  const outputs = root.querySelectorAll<HTMLElement>("[data-demo-output]");
  const bars = root.querySelectorAll<HTMLElement>("[data-level-bar]");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  let ready = false;
  let visible = false;
  let paused = false;
  let frameRequest = 0;
  let previousTime = 0;
  let elapsed: number | null = null;
  let offset = 0;
  let travel = 72;
  let direction = 1;
  let steps = 0;
  let walkDelay = 0;
  let idleFrame = 1;
  let currentFrame = "idle-1";
  let lastBarUpdate = 0;

  function setFrame(name: string) {
    if (name === currentFrame) return;
    currentFrame = name;
    image.src = frameURL(name);
  }

  function setPhase(phase: string, message: string) {
    if (root.dataset.demoPhase === phase) return false;
    root.dataset.demoPhase = phase;
    status.textContent = message;
    return true;
  }

  function renderPlayback(time: number) {
    if (time < 408) {
      setPhase("intro", "Microphone out");
      setFrame(reducedMotion.matches ? "recording-hold" : `recording-intro-${Math.min(6, Math.floor(time / 68) + 1)}`);
    } else if (time < 2608) {
      setPhase("listening", "Listening · “I'll send the notes after lunch”");
      setFrame("recording-hold");
      if (!reducedMotion.matches && time - lastBarUpdate >= 80) {
        bars.forEach((bar, index) => {
          const level = 0.25 + 0.75 * Math.abs(Math.sin(time / 230 + index * 0.8));
          bar.style.transform = `scaleX(${level})`;
        });
        lastBarUpdate = time;
      }
    } else if (time < 2884) {
      setPhase("outro", "Microphone away");
      setFrame(reducedMotion.matches ? "idle-1" : `recording-intro-${Math.max(1, 6 - Math.floor((time - 2608) / 46))}`);
    } else if (time < 3884) {
      setPhase("processing", "Turning speech into text");
      setFrame("idle-1");
    } else if (time < 5084) {
      if (setPhase("done", "Pasted · right where your cursor was")) {
        outputs.forEach((output) => { output.textContent = "I'll send the notes after lunch."; });
      }
    } else {
      elapsed = null;
      play.disabled = false;
      play.textContent = "Replay dictation";
      setPhase("walking", reducedMotion.matches ? "Ready" : "Ready · walking along the edge");
    }
  }

  function tick(time: number) {
    frameRequest = 0;
    const delta = previousTime ? Math.min(time - previousTime, 100) : 0;
    previousTime = time;
    if (elapsed !== null) {
      elapsed += delta;
      renderPlayback(elapsed);
    } else if (!reducedMotion.matches) {
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
    schedule();
  }

  function schedule() {
    const running = ready && visible && !document.hidden && !paused;
    root.dataset.demoRunning = String(running);
    if (running && (elapsed !== null || !reducedMotion.matches)) {
      if (!frameRequest) frameRequest = requestAnimationFrame(tick);
    } else {
      cancelAnimationFrame(frameRequest);
      frameRequest = 0;
      previousTime = 0;
    }
  }

  play.disabled = true;
  framesReady.then(() => {
    ready = true;
    play.disabled = false;
    schedule();
  }).catch(() => {
    status.textContent = "Preview couldn't load. Refresh to try again.";
  });
  play.addEventListener("click", () => {
    elapsed = 0;
    lastBarUpdate = 0;
    play.disabled = true;
    play.textContent = "Playing demo…";
    outputs.forEach((output) => { output.textContent = "Your words appear here."; });
    paused = false;
    syncPause();
    renderPlayback(0);
    schedule();
  });
  function syncPause() {
    pause.setAttribute("aria-pressed", String(paused));
    pause.textContent = paused ? "Resume motion" : "Pause motion";
  }
  pause.addEventListener("click", () => {
    paused = !paused;
    syncPause();
    schedule();
  });
  function syncMotionPreference() {
    pause.hidden = reducedMotion.matches;
    if (reducedMotion.matches) {
      paused = false;
      offset = 0;
      crab.style.setProperty("--crab-offset", "0px");
      setFrame("idle-1");
    }
    if (elapsed === null) status.textContent = reducedMotion.matches ? "Ready" : "Ready · walking along the edge";
    syncPause();
    schedule();
  }
  new ResizeObserver(([entry]) => {
    travel = Math.min(72, Math.max(0, (entry.contentRect.height - 84) / 2 - 16));
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
