# ShoutOut 0.1.3

- Adds local language cleanup visibility in logs and History, including before, model, and after text.
- Fixes the standard cleanup prompt so the local model removes the abandoned `a...` in corrections like `a... actually`.
- Warms language cleanup in the background while disabling and clearing the MLX cache so idle app memory stays lower without making first use pay the full load cost.
- Tunes shortcut recording timing with a shorter initial hold and a tighter double-press window.
