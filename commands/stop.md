---
description: Stop the speech playing right now and clear everything queued behind it
---

Cut off auto-speak immediately: kill the sentence in flight and drop every turn
waiting in the queue. One-shot - speech is back to normal on the next turn.

This replaces the Escape key, which used to interrupt speech only because `say`
ran inside the hook's own process group. The speech queue deliberately runs
outside it (that is what lets it survive the hook and take turns across
sessions), so Escape no longer reaches it.

Run exactly this:

```bash
q=$(ls /tmp/auto-speak-queue/*.speak 2>/dev/null | wc -l | tr -d ' ')
killall say 2>/dev/null
rm -f /tmp/auto-speak-queue/*.speak 2>/dev/null
touch "/tmp/auto-speak-skip-next.${CLAUDE_CODE_SESSION_ID}" 2>/dev/null
echo "stopped; cleared ${q} queued"
true
```

- `killall say` stops the audio you can hear. The drainer treats that as "stop
  talking" and purges the rest on its own; the `rm` is belt and braces for items
  queued with no drainer alive to notice.
- The `touch` arms a one-shot skip so **this** reply is not read aloud. Without
  it, a command that means "be quiet" would answer you out loud.

Then confirm in ONE short line, mentioning how many queued turns you cleared.

## Notes

- Machine-wide, like the audio itself: it clears every session's pending speech,
  not just this one's. There is a single mouth, so there is a single queue.
- This is one-shot. The next turn in any session speaks normally. For lasting
  silence use `/auto-speak:mute` (holds until `/auto-speak:unmute`).
- `killall say` on its own does the same thing from any terminal, if you have one
  closer to hand than a Claude prompt.
- The same two commands are shipped as `scripts/stop.sh` for hotkeys and buttons
  (Keyboard Maestro, Stream Deck, a terminal). If `auto-speak-stop` is on PATH,
  run that instead of the inline commands above - it is the same logic.
