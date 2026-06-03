---
description: Switch auto-speak voice (lists installed voices, auditions on request)
argument-hint: "[voice name]"
---

Switch the auto-speak plugin's voice. Do not use emojis in your responses -
they are being spoken aloud.

The config file is `~/.claude/auto-speak.conf` (shell variables: VOICE, RATE,
MODE). Only change the VOICE line; preserve everything else. If the file does
not exist, create it with just the VOICE line.

The user's argument (may be empty): $ARGUMENTS

## If an argument was given

Match it against installed voices (`say -v '?'`), case-insensitively and
loosely - "zoe" should match "Zoe (Premium)", "tom" should match
"Tom (Enhanced)". If exactly one voice matches, update VOICE in the conf and
confirm in one short sentence. If several match, list them and ask which. If
none match, say so and list the installed Enhanced/Premium voices.

## If no argument was given

- List the quality voices installed: `say -v '?' | grep -iE "premium|enhanced"`
- Present a menu (use the AskUserQuestion tool if available) of those voices,
  marking the currently configured one, plus an option to audition before
  choosing and an option for the system default (empty VOICE).
- If the user wants auditions, play candidates one at a time at their
  configured RATE: `say -v "<Voice>" -r <RATE> "This is what I sound like
  reading your responses."` and let them pick afterward.
- If they have no Enhanced/Premium voices, point them at System Settings >
  Accessibility > Spoken Content > System Voice > Manage Voices (or VoiceOver
  Utility > Speech > Voice > Customize if that panel freezes - known macOS
  bug). Warn that Siri voices do not work with `say`.

Update the conf with the choice and confirm in one short sentence.

## Notes

- Takes effect on the very next response - no restart or reload needed.
- The new voice will speak your confirmation reply, so keep it short and let
  that be the audition.