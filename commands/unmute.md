---
description: Unmute auto-speak in every Claude session
---

Lift the global auto-speak mute. Keep your reply to one or two short sentences -
it will be spoken aloud, and that is the confirmation that speech is working
again.

Read the flag first (it records when the mute started), then remove it:

```bash
cat ~/.claude/auto-speak-mute 2>/dev/null; rm -f ~/.claude/auto-speak-mute
```

Confirm in one short sentence that auto-speak is back on in every session, and
mention how long it had been muted if the file gave you a timestamp.

## Notes

- Global and immediate, like the mute: every open Claude session speaks again on
  its next turn. Nothing to restart.
- If the file did not exist, auto-speak was not muted. Say that instead of
  claiming you changed something - and if the user thought it was muted, the
  meeting guard was probably the thing keeping it quiet.
- The meeting guard is independent of this flag. Unmuting while your microphone
  is still live will not produce speech until the mic is released. To check what
  the guard currently sees:

  ```bash
  python3 "${CLAUDE_PLUGIN_ROOT}/scripts/mic_in_use.py" --list
  ```

  It lists every audio input device and marks the live ones. `cat
  /tmp/auto-speak-skip.txt` shows the reason the last skipped turn stayed quiet.
