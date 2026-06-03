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
/plugin install auto-speak@coreyms
```

Restart Claude Code. Every response is now spoken with the system default
voice, and on first launch Claude will offer to walk you through setup.

## Configuration

Run `/auto-speak:setup` - Claude walks you through checking dependencies,
auditioning voices, and picking a speech rate and mode, then writes your
choices to `~/.claude/auto-speak.conf`:

```bash
VOICE="Tom (Enhanced)"   # any voice from `say -v '?'`; empty = system default
RATE=210                 # words per minute; macOS default is ~175
MODE="paragraph"         # sentence | paragraph | full | summary
TIMBRE=""                # pitch base (~30 deep to ~65 bright); empty = natural
```

The config is per machine and survives plugin updates (it lives outside the
plugin directory). If the configured voice isn't installed on a machine, the
hook falls back to the system default voice instead of going silent.

Quick toggles without the full setup:

```
/auto-speak:mode             # interactive menu
/auto-speak:mode full        # switch directly
/auto-speak:voice            # list/audition installed voices
/auto-speak:voice zoe        # fuzzy-matches "Zoe (Premium)"
/auto-speak:rate             # demo speeds, pick one
/auto-speak:rate 230         # set directly
/auto-speak:timbre           # demo pitch bases, pick one
/auto-speak:timbre 35        # deeper; 'default' restores natural pitch
```

Changes take effect on the next response - the hook re-reads the config every
turn.

- `sentence` - speaks up to the first sentence-ending punctuation
- `paragraph` - speaks up to the first blank line
- `full` - speaks the whole response (code blocks are stripped)
- `summary` - a headless `claude -p --model haiku` condenses the response into
  a couple of spoken sentences, always surfacing any questions Claude asked
  you. Requires the `claude` CLI; adds a small per-turn cost and a few seconds
  of latency before speech. Falls back to `paragraph` if the CLI is
  unavailable. (Recursion-safe: the headless run executes from /tmp, which the
  hook's headless-session filter already ignores.)

To stop playback at any time: `killall say`

## Pair it with voice input

This plugin covers the speaking half of the conversation. For the listening
half, Claude Code has a built-in `/voice` command (a native setting, not part
of this plugin) that lets you talk to Claude instead of typing. With both
enabled, the loop is fully hands-free: you speak, Claude answers out loud.

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