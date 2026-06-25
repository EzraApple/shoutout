# ShoutOut 0.1.6

- Tightens local language cleanup so commands stay commands instead of becoming assistant-style offers or promises.
- Preserves request details such as "me" and avoids dropping leading context like "the diff is".
- Adds safer quote handling: technical terms can be quoted when useful, while filler quote spam is rejected.
- Expands local model smoke coverage for transcript-derived overreach cases.
