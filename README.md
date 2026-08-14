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
MEETING_GUARD="mic"      # stay silent while the mic is live; "off" disables
MIC_IGNORE=""            # device-name substrings the meeting guard ignores
SPEAK_QUEUE="on"         # sessions take turns speaking; "off" = speak immediately
QUEUE_MAX_STALE=0        # drop a queued turn older than N seconds; 0 = never drop
QUEUE_ANNOUNCE="auto"    # say who is talking when the voice changes sessions
QUEUE_LABEL="name"       # session name, else project dir; "session" = also use
                         # Claude Code's derived names (e.g. "autoflask-3d")
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
  unavailable. (Recursion-safe: the headless run is filtered out by the
  background-session gates below.)

To stop playback at any time: `killall say`

## Not talking over you

Two independent layers keep auto-speak from interrupting a meeting. Both are
**global** - every Claude session on the machine obeys them, which matters when
you run five or seven at once, and neither needs per-session bookkeeping because
the hook re-reads them on every turn.

### The meeting guard (automatic, on by default)

If anything is capturing audio input, the turn is not spoken. That covers Teams,
Zoom, Google Meet in a browser, Slack huddles, dictation and recordings, with no
calendar integration and no per-app detection: speech stops when the call starts
and comes back when it ends, in every session at once. There is nothing to
remember and nothing to undo.

`scripts/mic_in_use.py` reads CoreAudio's
`kAudioDevicePropertyDeviceIsRunningSomewhere` - the flag behind the orange mic
dot in the menu bar - through `ctypes`. No compiler, no cached binary, no
privacy permission, works on Intel and Apple Silicon, ~110ms per turn. Only
**input** devices count, so `say` (output) can never trip the guard on itself.

See what the guard sees:

```bash
python3 ~/.claude/plugins/cache/coreyms/auto-speak/*/scripts/mic_in_use.py --list
```

```
idle   MacBook Pro Microphone
IN-USE Microsoft Teams Audio
idle   ZoomAudioDevice
```

Tuning, in `~/.claude/auto-speak.conf`:

- `MEETING_GUARD="off"` disables it (you take calls on headphones and want
  speech anyway).
- `MIC_IGNORE="loopback,blackhole"` ignores devices whose name contains any of
  those substrings - the fix if a virtual/loopback driver reports itself as
  permanently running and mutes you for good. `/tmp/auto-speak-skip.txt` names
  the device that caused each skip, so you can see which one to add.

If the probe cannot run (no `python3`, CoreAudio unavailable) the guard **fails
open** and speaks: a missed mute beats silently losing speech forever.

### The mute switch (manual, for what the guard cannot see)

```
/auto-speak:stop      # shut up NOW: kill the sentence and clear the queue (one-shot)
/auto-speak:mute      # silence every session until you unmute
/auto-speak:unmute    # speech returns everywhere
```

`/auto-speak:stop` is the interrupt. Escape used to serve this purpose, but only
as a side effect: `say` ran inside the hook's process group, so cancelling the
turn killed the audio with it. The queue deliberately runs outside that group -
that is what lets speech survive the hook and take turns between sessions - so
Escape cannot reach it any more. The command kills the current utterance, clears
everything queued behind it, and arms a one-shot skip so its own confirmation is
not read aloud; the next turn speaks normally. `killall say` from any terminal
does the same thing (the drainer treats death-by-signal as "stop talking" and
purges the rest).

For someone at your desk, a room full of people, a call on another device, or a
fleet of agents you want quiet. The mute has no expiry - it holds until you
unmute. Under the hood it is the file `~/.claude/auto-speak-mute`
(`touch`/`rm` works just as well), and `/auto-speak:mute` also runs `killall
say` so the current utterance stops mid-word instead of finishing.

## Taking turns (several Claudes, one mouth)

Run five or seven sessions at once and they used to finish together and talk over
each other, losing both messages in the overlap. Now they queue: one voice at a
time, oldest turn first, nothing dropped.

The hook does not speak any more. It spools the text to
`/tmp/auto-speak-queue/` and hands off to `scripts/speak_queue.py`, which speaks
the backlog serially.

When the queue makes sessions take turns, each utterance says who is talking -
"From Survey QA Framework: ..." - but only when the voice actually changes
session, so a single session never narrates its own name at you.
`QUEUE_ANNOUNCE="always"` labels every turn, `"off"` never does.

The name comes from the session itself. Claude Code keeps a record per live
session at `~/.claude/sessions/<pid>.json` holding its `name` and a
`nameSource`, where `"derived"` marks the auto-generated `<project>-<suffix>`
nobody chose. So a session you have named announces by that name, and an unnamed
one falls back to its project directory. If you run several sessions in the *same*
repo, that fallback is ambiguous by definition - either name them, or set
`QUEUE_LABEL="session"` to use the derived names (`autoflask-3d`), which are
unique per session but read less naturally.

Two properties worth knowing, because they are what make this safe:

- **The hook returns in milliseconds** instead of blocking for the length of the
  queue. Serializing inside the hook would hold that session's Stop hook open
  while it waited, and the hook's 300s timeout would eventually drop the message
  the queue exists to save. The drainer is spawned in a **new session**
  (`start_new_session=True`), which escapes the process group Claude Code
  SIGKILLs when the hook returns - so speech outlives the hook that queued it.
- **`killall say` stops everything**, not just the sentence you can hear. A
  backlog would otherwise make that command useless: kill one line, the next
  starts. The drainer notices `say` died by signal and purges the rest.

Queued items are re-checked at the moment they come up, not when they were
queued, so the guards still win over a stale backlog: a call that starts while
you are waiting drops your item, and `/auto-speak:mute` purges the whole queue
instead of muting "after it finishes". `QUEUE_MAX_STALE=90` additionally drops
anything that waited longer than 90 seconds; the default `0` never drops, on the
grounds that late speech beats lost speech. `SPEAK_QUEUE="off"` restores the old
speak-immediately behavior, and if `python3` is missing the hook falls back to it
automatically - overlapping audio, but never silence.

`/tmp/auto-speak-queue.log` records every queue decision (what spoke, how long
it waited, how many were behind it, what was dropped and why).

## Which sessions get spoken

Only sessions you are actually interacting with. User-scoped Stop hooks fire
for **every** claude session on the machine - including headless `claude -p`
children spawned by other plugins, SDK-driven background agents, and
scheduled/cron runs - which used to produce "mystery audio" about things
never addressed to you. The hook now gates on:

1. the mute file (`~/.claude/auto-speak-mute`),
2. `CLAUDE_CODE_ENTRYPOINT` - interactive terminals run as `cli`; headless
   `claude -p` / SDK sessions run as `sdk-*` and are skipped,
3. a controlling terminal - the claude process that fired the hook must be
   attached to a tty; programmatically spawned sessions are detached,
4. the legacy /tmp cwd guard,
5. the meeting guard - a live microphone (checked last, so background sessions
   never pay for the probe; re-checked just before speaking in `summary` mode,
   where the haiku call is long enough to join a call in).

Multiple concurrent **interactive** sessions all speak - that is intended.
Every skipped session is logged with its reason to `/tmp/auto-speak-skip.txt`.

(In-process subagents - the Agent tool, Workflow agents - fire `SubagentStop`
rather than `Stop`, so they never trigger the hook at all; the sessions the
gates exist for are the separate headless claude processes.)

### Verifying the gates

Run a headless session from a normal directory and confirm it stays silent:

```bash
env -u CLAUDECODE claude -p --model haiku \
  'Reply with exactly: HEADLESS TEST - if you hear this out loud, the gate failed.'
```

You should hear nothing, and `/tmp/auto-speak-skip.txt` should show the
skipped session and which gate caught it:

```
2026-07-10 12:51:15 session=1fd289a4-... cwd=/Users/corey skipped: headless entrypoint sdk-cli
```

Then confirm the positive path - an interactive session's hook still speaks:

```bash
echo '{"cwd":"'$PWD'","last_assistant_message":"Interactive gate test passed: this should be spoken aloud."}' \
  | bash "$(ls -d ~/.claude/plugins/cache/coreyms/auto-speak/*/scripts/auto-speak.sh | tail -1)"
```

If audio is missing when it shouldn't be, `/tmp/auto-speak-skip.txt` says why
the session was skipped; if something speaks that shouldn't have,
`/tmp/auto-speak-last.txt` names the session that did it.

## Pair it with voice input

This plugin covers the speaking half of the conversation. For the listening
half, Claude Code has a built-in `/voice` command (a native setting, not part
of this plugin) that lets you talk to Claude instead of typing. With both
enabled, the loop is fully hands-free: you speak, Claude answers out loud.

## How it works

A `Stop` hook receives Claude Code's JSON payload on stdin, extracts
`last_assistant_message` with `jq`, strips markdown that reads badly aloud
(code fences, backticks, bold/italic markers, heading hashes, link URLs), and
spools the result for `scripts/speak_queue.py`, which speaks one turn at a time
across every session on the machine. With the queue off, or without `python3`,
the hook calls `say` itself.

## Lessons baked in (learned the hard way)

- **Foreground only.** Claude Code SIGKILLs the hook's process group on exit,
  so backgrounding the speak (even with `nohup`/`disown`) silently kills it.
  The hook declares a 300s timeout instead and speaks in the foreground.
- **`last_assistant_message`** is the payload field carrying the response text.
- **macOS has no `timeout` command.** Scripts that use it fail silently.
- **User-scoped hooks fire for headless sessions too.** Plugins that spawn
  background `claude -p` runs (e.g. the remember plugin) would have their
  output spoken aloud. A cwd-based guard is not enough - plugins run their
  children from arbitrary directories - so the hook gates on session type
  (entrypoint + controlling tty; see "Which sessions get spoken").
- The last spoken text (+ its session id) is written to
  `/tmp/auto-speak-last.txt`, and every skipped session with its reason to
  `/tmp/auto-speak-skip.txt`, for diagnosing mystery or missing audio.
- **Meeting apps are useless as a signal; the microphone is the signal.** Teams
  and Slack run all day, so process presence says nothing about being in a call.
  Power-management assertions are held by video playback too. A live audio
  *input* device is the one thing that means "someone is listening to you right
  now", and CoreAudio reports it for free, for every app, with no permission
  prompt.
- **A guard that can silence you forever has to fail open.** If the mic probe
  errors, prints something unexpected, or has no interpreter to run in, the hook
  speaks anyway. The failure mode of a wrong mute is a plugin that appears
  broken with no error message.
- **`start_new_session=True` is the escape hatch from hook teardown.** The
  process-group SIGKILL that kills backgrounded children does not reach a child
  in its own session, which is what lets the speech queue outlive the hook.
  Verified by SIGKILLing a hook's whole process group and watching the child
  keep running.
- **A two-step lock is not a lock.** The first version of the queue took the
  speaking lock by `mkdir`, then wrote its pid inside. A rival drainer read the
  lock in that gap, saw no owner, assumed it was abandoned, stole it - and both
  spoke at once, which is the exact bug the queue was written to fix. It now
  hardlinks a file that already contains the pid, so the name cannot appear
  before its contents. Locks that a SIGKILL can strand also need a liveness
  check, or one crash mutes the machine for good.