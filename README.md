# claude-auto-speak

Speaks Claude Code's responses aloud after each turn using macOS built-in `say`.
Fully local - no API keys, no network, no cost.

## Prerequisites

- macOS (uses the built-in `say` command)
- `jq` (`brew install jq`)
- A nice voice (optional but recommended): download an **Enhanced** or **Premium**
  voice under System Settings > Accessibility > Spoken Content > System Voice >
  Manage Voices. If that panel freezes (known macOS bug), use VoiceOver Utility >
  Speech > Voice dropdown > Customize instead.
  Note: **Siri voices do not work with `say`** - don't bother downloading them.

## Install

```
/plugin marketplace add coreyms/claude-auto-speak
/plugin install auto-speak@corey-plugins
```

Restart Claude Code. Every response is now spoken.

## Configuration

Knobs at the top of `scripts/auto-speak.sh`:

```bash
VOICE="Tom (Enhanced)"   # any voice from `say -v '?'`
RATE=210                 # words per minute; macOS default is ~175
MODE="paragraph"         # sentence | paragraph | full
```

- `sentence` - speaks up to the first sentence-ending punctuation
- `paragraph` - speaks up to the first blank line
- `full` - speaks the whole response (code blocks are stripped)

To stop playback at any time: `killall say`

## How it works

A `Stop` hook receives Claude Code's JSON payload on stdin, extracts
`last_assistant_message` with `jq`, strips markdown that reads badly aloud
(code fences, backticks, bold/italic markers, heading hashes, link URLs),
and pipes the result to `say`.

## Lessons baked in (learned the hard way)

- **Foreground only.** Claude Code SIGKILLs the hook's process group on exit,
  so backgrounding the speak (even with `nohup`/`disown`) silently kills it.
  The hook declares a 300s timeout instead and speaks in the foreground.
- **`last_assistant_message`** is the payload field carrying the response text.
- **macOS has no `timeout` command.** Scripts that use it fail silently.
- **User-scoped hooks fire for headless sessions too.** Plugins that spawn
  background `claude -p` runs (e.g. the remember plugin, which runs from /tmp)
  would have their output spoken aloud. The script exits early when the
  payload's `cwd` is under /tmp.
- The last spoken text is written to `/tmp/auto-speak-last.txt` for diagnosing
  any mystery audio.