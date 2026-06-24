# ShoutOut 0.1.5

- Improves local language cleanup with a more reliable cleanup model, stricter validation, and visible before/model/after history details.
- Keeps casual cleanup casual while normal and formal cleanup remove unnecessary speech fillers such as extra "like".
- Fixes short hold-to-record timing so the 120 ms hold threshold is based on the actual key press, not recorder startup latency.
- Redacts legacy cleanup text from diagnostics exports and stops writing raw cleanup text to runtime logs.
- Cleans retired local cleanup model caches after update.
