---
description: Walk the user through configuring auto-speak (voice, rate, mode)
---

Walk the user through configuring the auto-speak plugin on this machine. Be
conversational and do one step at a time. The result is a config file at
`~/.claude/auto-speak.conf`.

## 1. Check dependencies

- Run `which jq`. If missing, tell the user to run `brew install jq` (the hook
  is silent without it) and wait for confirmation.
- Confirm `say` works: `say "Setup is starting"` so the user hears audio output
  is functional.

## 2. Pick a voice

- List good installed voices: `say -v '?' | grep -iE "premium|enhanced"` and
  also show a few standard en_US voices if none are enhanced.
- If no Enhanced/Premium voices are installed, recommend downloading one:
  System Settings > Accessibility > Spoken Content > System Voice > Manage
  Voices. If that panel freezes (known macOS bug), use VoiceOver Utility >
  Speech > Voice dropdown > Customize instead. Warn that SIRI VOICES DO NOT
  WORK with `say` - do not download those.
- Audition candidates the user is interested in, one at a time:
  `say -v "<Voice Name>" "This is what I sound like reading your responses."`
- Let the user pick. An empty voice means the system default.

## 3. Pick a rate

Demo a few speeds with the chosen voice, e.g. 175 (macOS default), 210, 230:
`say -v "<Voice>" -r 210 "This is two hundred ten words per minute."`

## 4. Pick a mode

Explain the three options:
- `sentence` - speaks just the first sentence (a spoken headline)
- `paragraph` - speaks up to the first blank line (recommended default)
- `full` - reads the entire response (code blocks are stripped)

## 5. Write the config

Write the choices to `~/.claude/auto-speak.conf` in shell-variable form, e.g.:

```bash
VOICE="Tom (Enhanced)"
RATE=210
MODE="paragraph"
```

## 6. Test end to end

Run the plugin's hook script directly with a simulated payload so the user
hears the real pipeline (use the actual plugin path from
`${CLAUDE_PLUGIN_ROOT}` if available, otherwise locate auto-speak.sh under
`~/.claude/plugins/cache/`):

```bash
echo '{"cwd":"'"$PWD"'","last_assistant_message":"Setup is complete. This is how your responses will sound from now on."}' | bash <path-to>/scripts/auto-speak.sh
```

Confirm the user heard it. Remind them: settings live in
`~/.claude/auto-speak.conf` (re-run this command anytime to change them), and
`killall say` stops playback mid-readout.