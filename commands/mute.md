---
description: Mute auto-speak in every Claude session until /auto-speak:unmute
---

Mute the auto-speak plugin globally and cut off any speech already in flight.
Keep your reply to one short line - the point of this command is silence.

Run both of these, in this order:

```bash
{ echo "muted $(date '+%Y-%m-%d %H:%M:%S') by session ${CLAUDE_SESSION_ID:-?}"; } > ~/.claude/auto-speak-mute
killall say 2>/dev/null; true
```

The first line creates the global mute flag; the second stops the sentence that
is being spoken right now (that is the whole reason this command exists - the
flag alone would let the current utterance finish).

Then confirm in one short sentence: muted everywhere, `/auto-speak:unmute` to
bring it back.

## Notes

- This is global and takes effect immediately in ALL sessions, including the
  other Claude windows you have open. The Stop hook re-reads the flag file every
  turn, so there is no per-session state and nothing to restart.
- The mute has no expiry - it stays until `/auto-speak:unmute`. Your own
  confirmation reply will not be spoken, which is the expected behavior.
- If the file already exists, auto-speak was already muted. Say so briefly and
  still run `killall say`.
- You do not need this just because you are joining a call: the meeting guard
  already keeps auto-speak silent on its own whenever the microphone is live.
  This command is for the cases the guard cannot see - someone walked up to your
  desk, a room full of people, a phone call on another device.
