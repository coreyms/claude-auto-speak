---
description: Set auto-speak speech rate in words per minute
argument-hint: "[words per minute, e.g. 210]"
---

Set the auto-speak plugin's speech rate. Do not use emojis in your responses -
they are being spoken aloud.

The config file is `~/.claude/auto-speak.conf` (shell variables: VOICE, RATE,
MODE). Only change the RATE line; preserve everything else. If the file does
not exist, create it with just the RATE line.

The user's argument (may be empty): $ARGUMENTS

## If an argument was given

If it is a number between 90 and 400, update RATE in the conf and confirm in
one short sentence. Outside that range, sanity-check with the user first
(below ~90 is painfully slow, above ~400 is unintelligible).

## If no argument was given

- Read the current conf and tell the user the current rate.
- Offer to demo a few speeds with their configured voice, one at a time:
  `say -v "<VOICE>" -r 175 "This is one hundred seventy five words per minute,
  the macOS default."` - suggest 175, 210, 230, and 260 as reference points.
- Present a menu (use the AskUserQuestion tool if available) with those
  reference speeds, marking the closest to their current rate, plus the
  option to type a custom number.

Update the conf with the choice and confirm in one short sentence.

## Notes

- Takes effect on the very next response - no restart or reload needed.
- The confirmation reply will be spoken at the NEW rate, so it doubles as
  the test.