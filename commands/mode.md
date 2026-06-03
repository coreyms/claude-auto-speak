---
description: Switch auto-speak mode (sentence | paragraph | full | summary)
argument-hint: "[sentence|paragraph|full|summary]"
---

Switch the auto-speak plugin's speech mode. Do not use emojis in your
responses - they are being spoken aloud.

The config file is `~/.claude/auto-speak.conf`. It contains shell variables
(VOICE, RATE, MODE). Only change the MODE line; preserve everything else. If
the file does not exist, create it with just the MODE line.

The user's argument (may be empty): $ARGUMENTS

## If an argument was given

If it is one of `sentence`, `paragraph`, `full`, or `summary` (accept case
variations), update MODE in the conf immediately and confirm in one short
sentence what the new mode does. If it is anything else, say it is not a
valid mode and show the four options.

## If no argument was given

Read the current conf, then present a menu (use the AskUserQuestion tool if
available) with the four modes, noting which one is currently active:

- `sentence` - speaks just the first sentence (a spoken headline)
- `paragraph` - speaks up to the first blank line (fast, free)
- `full` - reads the entire response (code blocks are stripped)
- `summary` - a small headless Claude condenses each response and always
  includes questions directed at the user (best quality, adds a few seconds
  of latency and a tiny per-turn cost)

Update the conf with the user's choice and confirm in one short sentence.

## Notes

- Takes effect on the very next response - the hook re-reads the conf every
  turn, so no restart or reload is needed.
- Do not speak a test phrase; the confirmation reply itself will be spoken.