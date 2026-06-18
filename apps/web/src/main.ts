import "@fontsource-variable/space-grotesk";
import "@fontsource/pixelify-sans/500.css";
import "@fontsource/pixelify-sans/600.css";
import "./styles.css";

const now = () => window.performance?.now?.() ?? Date.now();
const requestFrame = (callback: FrameRequestCallback) =>
  window.requestAnimationFrame?.(callback) ?? window.setTimeout(() => callback(now()), 16);
const cancelFrame = (frameId: number) => {
  if (window.cancelAnimationFrame) {
    window.cancelAnimationFrame(frameId);
  } else {
    window.clearTimeout(frameId);
  }
};

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const compactViewport = window.matchMedia("(max-width: 680px)");

const header = document.querySelector<HTMLElement>(".site-header");
const brandLink = document.querySelector<HTMLAnchorElement>(".brand");

if (header) {
  let ticking = false;

  const syncHeader = () => {
    header.classList.toggle("is-floating", window.scrollY > 24);
    ticking = false;
  };

  syncHeader();

  window.addEventListener(
    "scroll",
    () => {
      if (!ticking) {
        requestFrame(syncHeader);
        ticking = true;
      }
    },
    { passive: true },
  );
}

brandLink?.addEventListener("click", (event) => {
  event.preventDefault();
  window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}`);

  const targetScrollY = !compactViewport.matches && window.scrollY <= 24 ? 72 : 0;
  header?.classList.toggle("is-floating", targetScrollY > 24);

  const scrollToTarget = () => {
    document.documentElement.scrollTop = targetScrollY;
    document.body.scrollTop = targetScrollY;
    window.scrollTo(0, targetScrollY);
    header?.classList.toggle("is-floating", targetScrollY > 24);
  };

  scrollToTarget();
  requestFrame(scrollToTarget);
});

const railTrack = document.querySelector<HTMLElement>(".rail-track");
const railCrab = document.querySelector<HTMLElement>(".rail-crab");

if (railTrack && railCrab) {
  const crossingDuration = 27_000;
  let crabX = 0;
  let direction = 1;
  let lastFrame = now();
  let frameId = 0;

  const trackWidth = () => railTrack.clientWidth;
  const crabWidth = () => railCrab.offsetWidth;
  const minCrabX = () => -crabWidth();
  const maxCrabX = () => trackWidth();
  const crossingDistance = () => trackWidth() + crabWidth();

  const syncCrab = () => {
    railCrab.style.setProperty("--rail-crab-x", `${crabX.toFixed(2)}px`);
  };

  const setDirection = (nextDirection: 1 | -1) => {
    direction = nextDirection;
    railTrack.classList.toggle("is-reversing", direction === -1);
  };

  const syncDirectionFromHover = () => {
    setDirection(railTrack.matches(":hover") ? -1 : 1);
  };

  const tick = (timestamp: number) => {
    syncDirectionFromHover();

    const maxX = maxCrabX();
    const minX = minCrabX();
    const elapsed = Math.min(timestamp - lastFrame, 80);
    const speed = crossingDistance() / crossingDuration;

    lastFrame = timestamp;
    crabX += direction * speed * elapsed;

    if (maxX > 0 && direction === 1 && crabX > maxX) {
      crabX = minX;
    } else if (direction === -1 && crabX < minX) {
      crabX = maxX;
    }

    syncCrab();
    frameId = requestFrame(tick);
  };

  const startRailCrab = () => {
    cancelFrame(frameId);

    if (reduceMotion.matches) {
      crabX = 0;
      syncCrab();
      railTrack.classList.remove("is-reversing");
      return;
    }

    lastFrame = now();
    frameId = requestFrame(tick);
  };

  railTrack.addEventListener("pointerenter", () => setDirection(-1));
  railTrack.addEventListener("pointerleave", () => setDirection(1));
  railTrack.addEventListener("mouseenter", () => setDirection(-1));
  railTrack.addEventListener("mouseleave", () => setDirection(1));

  window.addEventListener(
    "resize",
    () => {
      crabX = Math.min(Math.max(crabX, minCrabX()), maxCrabX());
      syncCrab();
    },
    { passive: true },
  );

  startRailCrab();

  if (typeof reduceMotion.addEventListener === "function") {
    reduceMotion.addEventListener("change", startRailCrab);
  } else if (typeof reduceMotion.addListener === "function") {
    reduceMotion.addListener(startRailCrab);
  }
}

const checklistRows = document.querySelectorAll<HTMLButtonElement>(".setting-row[data-checklist-key]");
const checklistStorageKey = "shoutout.permissionsChecklist";

const readChecklistState = () => {
  try {
    const rawState = window.sessionStorage.getItem(checklistStorageKey);
    return rawState ? (JSON.parse(rawState) as Record<string, boolean>) : {};
  } catch {
    return {};
  }
};

const writeChecklistState = (state: Record<string, boolean>) => {
  try {
    window.sessionStorage.setItem(checklistStorageKey, JSON.stringify(state));
  } catch {
    // Private browsing or blocked storage should not break the checklist UI.
  }
};

if (checklistRows.length > 0) {
  const checklistState = readChecklistState();

  const syncChecklistRow = (row: HTMLButtonElement, checked: boolean) => {
    row.classList.toggle("is-checked", checked);
    row.setAttribute("aria-pressed", String(checked));
  };

  checklistRows.forEach((row) => {
    const key = row.dataset.checklistKey;

    if (!key) {
      return;
    }

    syncChecklistRow(row, Boolean(checklistState[key]));

    row.addEventListener("click", () => {
      checklistState[key] = !checklistState[key];
      syncChecklistRow(row, checklistState[key]);
      writeChecklistState(checklistState);
    });
  });
}

const agentJokes = [
  {
    setup: "The microphone joined a union.",
    punchline: "Its only demand was less mouth breathing.",
  },
  {
    setup: "The shortcut key got a performance review.",
    punchline: "It was told to stop taking so much Fn credit.",
  },
  {
    setup: "The loading dots started a group chat.",
    punchline: "Nobody said anything, but the pacing was excellent.",
  },
  {
    setup: "The settings panel became self-aware.",
    punchline: "It immediately asked for permission to ask for permission.",
  },
  {
    setup: "I asked the app to think outside the box.",
    punchline: "It pointed at this box and said budget constraints.",
  },
  {
    setup: "The permissions dialog got into management.",
    punchline: "Now every decision needs four approvals.",
  },
  {
    setup: "The pasteboard said it could keep things casual.",
    punchline: "Then introduced your text to every app it knows.",
  },
  {
    setup: "The waveform went to business school.",
    punchline: "All peaks, no revenue.",
  },
  {
    setup: "The cursor started meditating.",
    punchline: "It blinked until everyone called it focus.",
  },
  {
    setup: "The transcript hired a copy editor.",
    punchline: "Then pasted over the edits for consistency.",
  },
  {
    setup: "The input field said it needed space.",
    punchline: "So the app gave it a global shortcut.",
  },
  {
    setup: "The local model stopped taking calls.",
    punchline: "It said the cloud could leave a voicemail.",
  },
  {
    setup: "The microphone started a podcast.",
    punchline: "Episode one was just room tone with ambition.",
  },
  {
    setup: "The onboarding flow became a life coach.",
    punchline: "Its advice was mostly open System Settings.",
  },
  {
    setup: "The floating nav got promoted.",
    punchline: "Now it hovers over everyone.",
  },
  {
    setup: "The chat input asked for work-life balance.",
    punchline: "It settled for one line at a time.",
  },
  {
    setup: "The keyboard shortcut got nervous on launch day.",
    punchline: "Understandable. It was under a lot of press.",
  },
  {
    setup: "The privacy policy tried to be exciting.",
    punchline: "Best it could do was nothing leaves your Mac.",
  },
  {
    setup: "The app asked macOS for a tiny favor.",
    punchline: "macOS opened a pane and made it official.",
  },
  {
    setup: "The build log tried standup.",
    punchline: "It passed, which is the rarest punchline.",
  },
];

document.querySelectorAll<HTMLElement>("[data-agent-chat]").forEach((chat) => {
  const form = chat.querySelector<HTMLFormElement>("[data-agent-input]");
  const input = form?.querySelector<HTMLInputElement>('input[name="message"]');
  let jokeIndex = 0;
  let nextReplyPart: "setup" | "punchline" = "setup";
  let replyTimeout = 0;
  let pendingTyping: HTMLElement | null = null;

  if (!form || !input) {
    return;
  }

  const createMessage = (role: "assistant" | "user", text: string, isTyping = false) => {
    const message = document.createElement("div");
    const avatar = document.createElement("span");
    const body = document.createElement("p");

    message.className = `agent-message ${role}-message`;
    avatar.className = "agent-avatar";
    avatar.textContent = role === "assistant" ? "ai" : "me";
    if (isTyping) {
      const dots = document.createElement("span");

      message.classList.add("is-typing");
      body.setAttribute("aria-label", "AI is typing");
      dots.className = "typing-dots";

      for (let index = 0; index < 3; index += 1) {
        dots.append(document.createElement("span"));
      }

      body.append(dots);
    } else {
      body.textContent = text;
    }

    message.append(avatar, body);
    return message;
  };

  const keepLatestMessages = () => {
    const messages = Array.from(chat.querySelectorAll<HTMLElement>(".agent-message"));

    messages.slice(0, Math.max(0, messages.length - 2)).forEach((message) => message.remove());
  };

  const appendMessage = (role: "assistant" | "user", text: string) => {
    chat.insertBefore(createMessage(role, text), form);
    keepLatestMessages();
  };

  const showTypingIndicator = () => {
    pendingTyping?.remove();
    pendingTyping = createMessage("assistant", "", true);
    chat.insertBefore(pendingTyping, form);
    keepLatestMessages();
  };

  const submitMessage = () => {
    const text = input.value.trim();

    if (!text) {
      return;
    }

    window.clearTimeout(replyTimeout);
    pendingTyping?.remove();
    pendingTyping = null;

    input.value = "";
    appendMessage("user", text);
    showTypingIndicator();

    const joke = agentJokes[jokeIndex % agentJokes.length];
    const reply = joke[nextReplyPart];

    if (nextReplyPart === "setup") {
      nextReplyPart = "punchline";
    } else {
      nextReplyPart = "setup";
      jokeIndex += 1;
    }

    replyTimeout = window.setTimeout(() => {
      pendingTyping?.remove();
      pendingTyping = null;
      appendMessage("assistant", reply);
    }, 1_150);
  };

  keepLatestMessages();

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    submitMessage();
  });

  input.addEventListener("keydown", (event) => {
    if (event.key !== "Enter") {
      return;
    }

    event.preventDefault();
    submitMessage();
  });
});

type TrackableWindow = Window & {
  dataLayer?: Array<Record<string, unknown>>;
  plausible?: (eventName: string, options?: { props?: Record<string, string> }) => void;
};

const trackEvent = (eventName: string, props: Record<string, string>) => {
  const trackableWindow = window as TrackableWindow;

  trackableWindow.plausible?.(eventName, { props });
  trackableWindow.dataLayer?.push({ event: eventName, ...props });

  if (typeof window.CustomEvent === "function") {
    window.dispatchEvent(new CustomEvent("shoutout:analytics", { detail: { eventName, props } }));
  }
};

document.querySelectorAll<HTMLElement>("[data-track-event]").forEach((element) => {
  element.addEventListener("click", () => {
    trackEvent(element.dataset.trackEvent ?? "interaction", {
      label: element.dataset.trackLabel ?? element.textContent?.trim() ?? "unknown",
      href: element instanceof HTMLAnchorElement ? element.href : "",
    });
  });
});
