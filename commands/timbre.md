---
description: Set auto-speak timbre (voice pitch base - deeper or brighter)
argument-hint: "[pitch base 30-65, or 'default']"
---

Set the auto-speak plugin's timbre (pitch base). Do not use emojis in your
responses - they are being spoken aloud.

The config file is `~/.claude/auto-speak.conf` (shell variables: VOICE, RATE,
MODE, TIMBRE). Only change the TIMBRE line (add it if absent); preserve
everything else. TIMBRE is a pitch-base number passed to Apple's embedded
speech command `[[pbas N]]` - roughly 30 is deep, 45-50 is typical, 65 is
bright. An empty value means the voice's natural pitch.

The user's argument (may be empty): $ARGUMENTS

## If an argument was given

- `default`, `off`, `reset`, or `natural`: set `TIMBRE=""` and confirm the
  voice is back to its natural pitch.
- A number between 20 and 90: update TIMBRE and confirm in one short
  sentence. Outside that range, sanity-check with the user first.

## If no argument was given

- Read the current conf and tell the user the current timbre (or "natural"
  if unset).
- Offer to demo a few settings with their configured voice and rate, one at
  a time, e.g.:
  `say -v "<VOICE>" -r <RATE> "[[pbas 35]] This is a deeper pitch base of thirty five."`
  Suggest 35 (deep), 45 (typical), 55 (brighter) as reference points.
- Present a menu (use the AskUserQuestion tool if available): deep 35,
  natural (unset), bright 55, or a custom number.

Update the conf with the choice and confirm in one short sentence.

## Notes

- Takes effect on the very next response - no restart or reload needed.
- Whether the pitch command is honored depends on the voice; the Enhanced
  and Premium voices generally support it. If a demo sounds identical at
  every value, that voice ignores pitch commands - tell the user honestly
  rather than setting a value that does nothing.
- The confirmation reply will be spoken with the NEW timbre, so it doubles
  as the test.
