const reply = "I'll send the notes after lunch.";
const recordingStart = 2400;
const recordingStop = recordingStart + 2608;
const transcriptionEnd = recordingStart + 3884;
const pasteTime = transcriptionEnd + 500;
const cycleDuration = 12600;
const steps = [
  { until: 1400, name: "typing" },
  { until: recordingStart - 250, name: "received" },
  { until: recordingStart, name: "focused" },
  { until: recordingStop, name: "recording" },
  { until: transcriptionEnd, name: "processing" },
  { until: pasteTime, name: "complete" },
  { until: 8000, name: "composing" },
  { until: 8250, name: "sending" },
  { until: 12300, name: "sent" },
  { until: cycleDuration, name: "reset" },
] as const;

export function createMessageLoop(root: HTMLElement) {
  const draft = root.querySelector<HTMLElement>("[data-message-draft]");
  let elapsed = 0;

  function renderStep(name: typeof steps[number]["name"], still = false) {
    root.dataset.messageStep = name;
    root.dataset.messageFocused = String(!still && name !== "typing" && name !== "received" && name !== "reset");
    if (draft) draft.textContent = name === "composing" || name === "sending" ? reply : "";
  }

  return {
    advance(delta: number): number | null {
      elapsed = (elapsed + delta) % cycleDuration;
      const step = steps.find(({ until }) => elapsed < until)!;

      if (root.dataset.messageStep !== step.name) {
        renderStep(step.name);
      }

      return elapsed >= recordingStart && elapsed < pasteTime
        ? elapsed - recordingStart : null;
    },
    reset(still: boolean) {
      elapsed = 0;
      renderStep(still ? "sent" : "typing", still);
    },
  };
}
