# Shout Out Implementation Plan

## Goal

Build a macOS-native, local-first dictation app with the Wispr Flow core loop: hold Fn to record, double-tap Fn for hands-free recording, transcribe locally, apply dictionary-aware cleanup, paste into the focused text field, and expose lightweight stats.

## Research Summary

- Wispr Flow asks for Microphone and Accessibility on macOS so it can listen and insert spoken words into other apps.
- Its default Mac interaction is hold Fn or double-tap Fn.
- The proven local architecture for this class of app is CGEvent tap, AVAudioEngine, WhisperKit, and clipboard plus Cmd-V insertion.
- WhisperKit can download and run Core ML Whisper models on device; large-v3-v20240930_626MB is the accuracy target, while tiny/base are better for setup/debugging.

## Milestones

### 1. Rebrand And Install Path

**Why:** The app should be a clean new repo named Shout Out, not a copy of Inputalk's product surface.

**Before:**
```swift
let package = Package(name: "Inputalk")
```

**After:**
```swift
let package = Package(name: "ShoutOut")
```

**Verify:** Static tests check bundle name, bundle id, README, Makefile, build script, and install command.

### 2. Core Text Processing

**Why:** The dictionary feature is mandatory for names and acronyms Whisper misses and should be testable without the app UI.

**Before:**
```swift
return postProcess(text)
```

**After:**
```swift
return TextPostProcessor.process(
    text,
    options: postProcessingOptions,
    dictionaryEntries: dictionaryStore.entries
)
```

**Verify:** Swift unit tests cover filler removal, spoken punctuation, custom dictionary aliases, and default product-term entries.

### 3. Dictionary UI And Persistence

**Why:** The user needs to add names/acronyms without editing code.

**Before:**
```swift
Toggle(isOn: $removeFillerWords) { ... }
```

**After:**
```swift
DictionarySettingsView(store: transcription.dictionaryStore)
```

**Verify:** Swift unit tests cover JSON persistence, add/update/delete, alias splitting, and corrupt-file fallback.

### 4. Usage Stats

**Why:** The user asked for viewable WPM/usage insights without analytics or cloud sync.

**Before:**
```swift
TextInserter.insertText(text)
```

**After:**
```swift
usageStats.record(finalText: result.finalText, duration: duration, model: transcription.selectedModel)
TextInserter.insertText(result.finalText)
```

**Verify:** Swift unit tests cover session count, word count, WPM, today vs all-time summaries, persistence, and clear history.

### 5. Recording UX

**Why:** Recording needs visible feedback and should optionally reduce competing audio.

**Before:**
```swift
showIndicator(state: .recording(level: 0))
```

**After:**
```swift
audioDucker.beginDuckingIfEnabled()
showIndicator(state: .recording(level: 0))
```

**Verify:** Static tests check the setting exists and the app restores audio when recording stops or fails.

## Test Inventory

1. Trims whitespace
2. Removes lowercase um
3. Removes uppercase uh
4. Removes filler with trailing comma
5. Preserves filler when disabled
6. Removes you-know filler
7. Collapses repeated spaces
8. Returns empty for whitespace input
9. Preserves existing punctuation
10. Replaces rep low with Replo
11. Replaces reply low with Replo
12. Replaces line ear with Linear
13. Replaces custom acronyms
14. Dictionary replacement is case-insensitive
15. Replaces multiple dictionary occurrences
16. Does not replace inside other words
17. Longer aliases win before shorter aliases
18. Custom acronym replacement
19. Custom phrase replacement
20. New line command
21. New paragraph command
22. Period command
23. Question mark command
24. Exclamation point command
25. Dictionary runs after spoken commands
26. Default entries include product terms
27. Spoken commands can be disabled
28. Dictionary store loads defaults when missing
29. Dictionary store trims phrase
30. Dictionary store splits aliases by comma/newline
31. Dictionary store ignores blank aliases
32. Dictionary store rejects empty phrase
33. Dictionary store persists entries
34. Dictionary store deletes entries
35. Dictionary store updates entries
36. Dictionary store tolerates corrupt JSON
37. Empty stats summary is zeroed
38. Stats record session count
39. Stats count words
40. Stats calculate WPM
41. Stats clamp tiny durations
42. Today summary filters old entries
43. All-time summary includes old entries
44. Stats persist to disk
45. Stats clear removes history
46. Recent sessions are newest first
47. Average WPM uses total duration
48. Punctuation does not inflate word count
49. Stats track total duration
50. Stats ignore blank final text
51. README names Shout Out
52. README documents make install
53. README preserves MIT attribution
54. README documents Microphone, Accessibility, and Input Monitoring
55. README documents custom dictionary entries
56. Makefile has install target
57. Package name is ShoutOut
58. Executable target is ShoutOut
59. Library target is ShoutOutCore
60. Test target is ShoutOutCoreTests
61. Info.plist bundle name is Shout Out
62. Info.plist executable is ShoutOut
63. Info.plist bundle id is com.ezraapple.shoutout
64. Info.plist has microphone usage text
65. Info.plist has accessibility usage text
66. Info.plist has input monitoring usage text
67. Entitlements allow audio input
68. Build script builds Shout Out.app
69. Build script signs for local use
70. Swift package builds

## Not In Scope

- App Store distribution: local install is enough.
- Cloud transcription: this should stay local-first.
- Full Wispr command mode: dictionary and basic cleanup are enough for this pass.
- App-specific tone profiles: explicitly not needed.

## Rollback

This is a new repo. Rollback is deleting the local checkout and GitHub repo, or reverting the latest commit.
