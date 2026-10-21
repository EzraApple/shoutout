# Dictionary

## Scope

Give users one local dictionary with a page in the existing app sidebar. A rule maps one or more misheard phrases to the preferred spelling. Apply the same rules across engines, before optional text cleanup.

The page includes search, add and edit sheets, delete confirmation, and a live sentence test. It uses the app’s existing visual components. There are no per-app modes, scripts, or additional models.

## Data and matching

`DictionaryStore` owns entries and atomic persistence in the app-support `dictionary.json`. Each entry keeps an ID, a preferred phrase, and its aliases. The shape remains compatible with the earlier dictionary experiment. Save the proposed list before publishing it to the UI. Reject blank fields, duplicate preferred phrases, and aliases already used by another entry.

`DictionaryReplacer` matches literal, case-insensitive whole phrases. Longer overlapping matches win. At equal lengths, earlier matches win; ties at the same position follow saved entry order. All matches refer to the original string, so replacement output cannot trigger another rule. Replacement output is literal text, including dollar signs and backslashes.

## Integration

The app delegate owns the shared store and injects it into the home window. Apply the dictionary once to the mechanically processed transcript, before optional local text cleanup. In the Mini trial, the corrected text becomes the cleanup input. Mini can delete words, but copies retained words with their spelling, case, and punctuation unchanged. When cleanup is off or fails, the corrected input is kept. Do not reapply dictionary rules after cleanup. Keep the cleanup audit fields as that stage’s actual input and output, including its model ID. The final history text and word counts use the cleanup result.

The sentence test calls the same replacement function used by dictation. It does not run transcription or the cleanup model.

The dated verification notes below describe earlier app versions. Their tone-rewrite behavior is not the Mini trial's behavior.

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

## Updated on October 19, 2026

Moved dictionary replacements before AI cleanup so the model receives corrected words and can apply the selected writing tone. Removed the special insertion-capitalization guard and the unused replacement metadata. The preview now explains that writing style follows dictionary replacement.

`make test` passed all 193 XCTest cases, 20 Swift Testing cases, and 287 repository checks. New cases cover Casual accepting lowercase dictionary words and cleanup being disabled. The release build and signature verification passed. The updated page copy was inspected in the native preview. No live model or microphone-to-paste check was run.

The sidebar now follows Dashboard, Insights, Dictionary, History, Settings. Permission checks live in a Settings section that uses the existing panel and button styles. Dashboard’s Setup Review button opens Settings and scrolls to that section. The native preview verified the new order, section layout, and Review navigation. Tests and the release build passed again. The UI tool could not resize this preview window, so the compact permissions layout remains unverified.

## Release verification on October 19, 2026

A separate preview started with an 820 × 620 content area to check the minimum window size. Dictionary, permission controls, and the footer fit without horizontal clipping. Dashboard Review reached the permission section, while the normal Settings link opened at the top. Only the preview's initial window size was changed; production source was restored afterward. Adding a rule and testing uppercase aliases and whole-phrase boundaries also passed in the native UI.

Real local MLX model checks passed the dictionary cases for Normal, Casual, and Formal. Normal rejected the model's `Replod` misspelling and retained the corrected `open Replo` baseline. Casual produced `open replo`, and Formal produced `Open Replo.` The existing long-request cleanup smoke case failed with `dropped_content` on both the unchanged baseline and the dictionary run; the full transcript was retained by the existing safety check. This is a model-quality limitation, and the unrelated test expectation was kept intact. The full unit/static suite again passed 193 XCTest cases, 20 Swift Testing cases, and 287 repository checks. No live microphone-to-paste check was run.
