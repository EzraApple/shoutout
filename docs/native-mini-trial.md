# Native Mini cleanup trial

Mini is an explicitly constructed local backend. The normal `LanguagePassService()` initializer, available model list, and saved default still use Llama. This change does not install or launch an app.

The trial uses `LanguagePassService(miniModelDirectory: directory)`. It runs the same native `MiniCleanupEngine` as the `MiniCleanupPanel` command. The directory contains a frozen Core ML model and its tokenizer assets. Model assets and actual dictation examples stay outside Git.

Mini predicts KEEP or DELETE for each source word. It copies retained words and their original spacing, spelling, case, and punctuation. It uses 256-token windows with 64-token overlap, averages each word's first-piece DELETE probabilities, and deletes at the frozen 0.98 threshold. It does not rewrite tone or repair punctuation.

The Mini path bypasses `LanguagePassValidator`, `LanguagePassMechanicalNormalizer`, and `LanguagePassOutputFormatter`. Its checks cover artifact identity, model output validity, finite predictions, and complete word coverage. A load or inference failure returns the exact source. A valid prediction that deletes all words is allowed.

Build and test from `apps/macos`:

```sh
swift build -c release --product MiniCleanupPanel
swift test --filter MiniCleanupTests
swift test --filter MiniLanguagePassIntegrationTests
```

The app-service replay test also accepts `MINI_TEST_MODEL_DIRECTORY` and `MINI_TEST_CASES`. Without those explicit private paths, the corpus replay is skipped; structural and failure-path tests still run. The replay expects the frozen 120 real-history inputs and 48 development challenge inputs, each with its previously recorded Mini output. It does not access the final test.

The panel reads JSONL rows with `id` and `source`, writes only to a `.private` directory, and refuses to overwrite output. Its trace mode includes token windows and word probabilities for parity checks. Use its usage message for the supported timing options. Warm timing covers tokenization, Core ML inference, word aggregation, and reconstruction. It excludes model compilation/loading, ASR, and paste.

Before an installed trial or default change, obtain separate approval. The native port must preserve the frozen development behavior; it is not a new quality improvement. The existing literal-text challenge failures still apply.
