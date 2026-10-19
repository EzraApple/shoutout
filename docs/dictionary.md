# Dictionary

## Scope

Give users one local dictionary with a page in the existing app sidebar. A rule maps one or more misheard phrases to the exact spelling the user wants. Keep the same behavior across engines and writing tones.

The page includes search, add and edit sheets, delete confirmation, and a live sentence test. It uses the app’s existing visual components. There are no per-app modes, scripts, or additional models.

## Data and matching

`DictionaryStore` owns entries and atomic persistence in the app-support `dictionary.json`. Each entry keeps an ID, a preferred phrase, and its aliases. The shape remains compatible with the earlier dictionary experiment. Save the proposed list before publishing it to the UI. Reject blank fields, duplicate preferred phrases, and aliases already used by another entry.

`DictionaryReplacer` matches literal, case-insensitive whole phrases. Longer overlapping matches win. At equal lengths, earlier matches win; ties at the same position follow saved entry order. All matches refer to the original string, so replacement output cannot trigger another rule. Replacement output is literal text, including dollar signs and backslashes.

## Integration

The app delegate owns the shared store and injects it into the home window. After the optional local language cleanup returns, apply the dictionary once before recording history and stats or inserting text. If a replacement includes the first word, preserve its capitalization during smart insertion. Keep the language-cleanup audit fields as that stage’s actual input and output. The final history text and word counts include dictionary changes.

The sentence test calls the same replacement function used by dictation. It does not run transcription, filler removal, or the language model.

## Verification

- Core tests cover whole-phrase boundaries, case, punctuation, overlaps, literal replacement strings, and replacement chains.
- Store tests cover validation, stable IDs, reload, legacy entries, and failed saves without changes to published data.
- Build the complete app and run the repository checks.
- Inspect the actual home window and exercise empty, populated, search, add, edit, conflict, preview, cancellation, deletion, and persistence states.

Debug builds accept `SHOUTOUT_DICTIONARY_PREVIEW=1` to open the dictionary without starting recording, models, or updates. Use a separate preview bundle identifier for disposable UI-test data.

## Checked on October 18, 2026

`make test` passed all 194 XCTest cases, 20 Swift Testing cases, and 287 repository checks. The host-architecture release build passed, including its MLX Metal runtime and local signature verification.

The actual home window and editor were inspected at normal and compact sizes. Interactive checks covered adding and editing entries, search by replacement phrase, no search results, replacement output, conflicting aliases, canceling edits, delete confirmation and cancellation, and persistence across launches. A damaged fixture file displayed the recovery state and disabled adding entries; restoring the fixture brought the saved entries back. Unit tests cover deletion and retrying a repaired file.

The installed signed app was preserved. Live microphone-to-paste dictation was not exercised with this build.
