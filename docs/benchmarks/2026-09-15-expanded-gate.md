# Expanded English replacement gate

Frozen before candidate inference on the new corpus. Compare English Parakeet
v2, Parakeet 1.1B with the NeMo-style frontend, and Canary 1B v2 against the same
Whisper Turbo 632 MB control used in prior rounds. Retain the prior corpus.

- New natural speech: shortest, median-duration and longest utterance per speaker
  from pinned LibriSpeech test-clean; no selection by recognition result.
- Long audio: four speakers concatenated to roughly one and three minutes,
  plus new continuous synthetic dictation. Concatenation is a duration stress
  test, not evidence about spontaneous long-form conversation.
- Dictation: two voices, varied rates, short requests, technical words, amounts,
  dates, negation, corrections, spoken punctuation and quoted instructions.
- Perturbations: fixed noise at 10/20 dB SNR, eight-second trailing silence,
  and a silence gate. Freeze references and audio hashes before inference.

Acceptance: raw case/punctuation-insensitive word error rate within 0.5 percentage
points of Whisper on new natural speech and within 1 point on new dictation;
no duration group over 2 points worse; no newly empty or severely truncated
speech, lost negation, or corrupted protected numbers attributable to the change.
Audit meaningful individual regressions rather than treating equivalent number
formatting or lowercase as quality failures. Require at least 2x median warm ASR
speedup overall and at least 25% lower reconstructed standard ASR+LM latency.

Run every file three times: first-file pass separately, two immediate repeats.
The first-file pass is a new-input measurement with a resident model, not a
cold-process benchmark. All styles pass through the unchanged LM; reuse identical
inputs explicitly. Any tweak must be separately labeled and retested on both the
new corpus and old fixtures; do not silently replace baseline observations.

A replacement also needs native app integration, retained word timing/filter
behavior, successful builds and existing unit/script checks. Existing unrelated
smoke failures are reported separately. Do not switch merely because aggregate
WER improves if consequential regressions remain unexplained.
