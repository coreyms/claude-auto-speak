#!/bin/bash

# Auto-speak hook for Claude Code
# Speaks Claude's response after each turn (Stop hook)
# Uses macOS built-in `say` (local, free) - no OpenAI API involved.

# Defaults - override per machine in ~/.claude/auto-speak.conf (run /auto-speak:setup)
VOICE=""            # empty = system default voice; or any name from `say -v '?'`
RATE=210            # words per minute; macOS default is ~175
MODE="paragraph"    # sentence | paragraph | full | summary
TIMBRE=""           # pitch base (~30 deep to ~65 bright); empty = voice default
MEETING_GUARD="mic" # mic = stay silent while the microphone is live; off = disable
MIC_IGNORE=""       # comma-separated device-name substrings the guard ignores

CONF="$HOME/.claude/auto-speak.conf"
[ -f "$CONF" ] && . "$CONF"

# Ensure homebrew tools (jq) and the claude CLI are findable even if the hook
# env has a minimal PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

json=$(cat)

cwd=$(echo "$json" | jq -r '.cwd // ""' 2>/dev/null)

# Record why a session was NOT spoken (diagnosing missing audio); see also
# /tmp/auto-speak-last.txt for what WAS spoken (diagnosing mystery audio).
skip() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') session=${CLAUDE_CODE_SESSION_ID:-?} cwd=${cwd:-?} skipped: $1" > /tmp/auto-speak-skip.txt
    exit 0
}

# ---- Speak ONLY for sessions the user is actually interacting with ----
# User-scoped Stop hooks fire for EVERY claude session on the machine, not just
# the terminals the user is watching. Known offenders: plugin-spawned `claude -p`
# children (remember writes memory notes from its own plugin dir), SDK-driven
# background agents, scheduled/cron runs. Multiple concurrent INTERACTIVE
# sessions all speak - that is intended.

# Gate 0 - mute switch: the file ~/.claude/auto-speak-mute silences EVERY
# session on the machine (it is re-read here each turn, so there is no
# per-session state to keep in sync). /auto-speak:mute creates it and cuts
# speech already in flight; /auto-speak:unmute removes it.
[ -f "$HOME/.claude/auto-speak-mute" ] && skip "muted by ~/.claude/auto-speak-mute"

# Gate 1 - headless entrypoints. Interactive terminal sessions run with
# CLAUDE_CODE_ENTRYPOINT=cli; `claude -p` and SDK-driven agents get sdk-*
# values. Hooks inherit the owning session's environment.
case "${CLAUDE_CODE_ENTRYPOINT:-}" in
    sdk*) skip "headless entrypoint $CLAUDE_CODE_ENTRYPOINT" ;;
esac

# Gate 2 - no controlling terminal. Walk up to the claude process that fired
# this hook: interactive sessions sit on a tty (ttysNNN); programmatically
# spawned ones are detached (ps tty "??"). If no claude ancestor is found
# (unexpected install shapes), fail open and rely on Gate 1 rather than
# muting every session.
p=$PPID
i=0
while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 8 ]; do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in
        claude|*/claude)
            tty=$(ps -o tty= -p "$p" 2>/dev/null | tr -d '[:space:]')
            case "$tty" in ''|'??') skip "claude (pid $p) has no tty" ;; esac
            break
            ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')
    i=$((i+1))
done

# Gate 3 - legacy cwd guard, kept as a cheap extra layer.
case "$cwd" in
    /tmp|/tmp/*|/private/tmp|/private/tmp/*) skip "cwd under /tmp" ;;
esac

# Claude Code sends the response text as last_assistant_message
msg=$(echo "$json" | jq -r '.last_assistant_message // ""' 2>/dev/null)

# Skip if empty or too short
[ -z "$msg" ] || [ ${#msg} -lt 30 ] && exit 0

# Gate 4 - meeting guard. Never talk over a live microphone: if anything is
# capturing audio input (Teams, Zoom, Meet in a browser, a Slack huddle,
# dictation, a recording) this turn goes unspoken. Checked fresh every turn, so
# no calendar, no timer and nothing to remember - speech stops when the call
# starts and returns when it ends, in all sessions at once.
# Undetermined (no python3, CoreAudio unavailable) fails OPEN and speaks: a
# missed mute beats silently losing speech forever. `say` is output-only, so it
# can never trip an input-scope check on itself.
mic_live() {
    [ "$MEETING_GUARD" = "mic" ] || return 1
    probe="$(dirname "$0")/mic_in_use.py"
    [ -f "$probe" ] || return 1
    for py in /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
        command -v "$py" >/dev/null 2>&1 || continue
        out=$(AUTO_SPEAK_MIC_IGNORE="$MIC_IGNORE" "$py" "$probe" 2>/dev/null)
        case "$out" in
            IN_USE*) mic_devices=${out#IN_USE	}; return 0 ;;
            IDLE)    return 1 ;;
        esac
        break   # python ran but said something unexpected - fail open
    done
    return 1
}

mic_live && skip "microphone in use (${mic_devices:-unknown})"

# Strip markdown that reads badly aloud: fenced code blocks, inline backticks,
# bold/italic markers, heading hashes, link targets (keep link text)
clean=$(echo "$msg" | sed -E '/^```/,/^```/d' | sed -E '
    s/`([^`]*)`/\1/g
    s/\*\*([^*]*)\*\*/\1/g
    s/\*([^*]*)\*/\1/g
    s/^#+ //
    s/\[([^]]*)\]\([^)]*\)/\1/g
')

# Strip emojis and pictographs - `say` pronounces them ("party popper", etc.)
clean=$(echo "$clean" | perl -CSD -pe 's/[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE00}-\x{FE0F}\x{200D}\x{2700}-\x{27BF}]//g' 2>/dev/null || echo "$clean")

case "$MODE" in
    sentence)
        # First sentence: flatten, cut at first . ! or ? (cap 300 chars as backstop)
        summary=$(echo "$clean" | tr '\n' ' ' | grep -oE '^[^.!?]*[.!?]' | head -c 300)
        [ -z "$summary" ] && summary=$(echo "$clean" | tr '\n' ' ' | head -c 300)
        ;;
    paragraph)
        # First paragraph: everything up to the first blank line
        summary=$(echo "$clean" | awk 'BEGIN{RS=""} NR==1' | tr '\n' ' ')
        ;;
    full)
        summary=$(echo "$clean" | tr '\n' ' ')
        ;;
    summary)
        # Let a small Claude decide what to say: condense the response and
        # surface any questions. Runs headless from /tmp so its own Stop hook
        # is filtered out by the cwd guard above (no recursion). CLAUDECODE is
        # unset so the CLI doesn't think it's nested (same pattern the
        # remember plugin uses). Costs a small haiku call per turn.
        if command -v claude >/dev/null 2>&1; then
            summary=$(echo "$clean" | (cd /tmp && env -u CLAUDECODE claude -p --model haiku \
                "Condense this assistant response into one to three short conversational sentences to be spoken aloud to the user. Lead with the bottom line. If the response asks the user any questions or needs a decision, you MUST include that. Output ONLY the text to speak - no preamble, no markdown, and absolutely no emojis (a speech synthesizer pronounces them literally).") \
                2>/dev/null | tr '\n' ' ')
        fi
        # Fall back to first paragraph if the CLI is missing or returned nothing
        [ -z "$summary" ] && summary=$(echo "$clean" | awk 'BEGIN{RS=""} NR==1' | tr '\n' ' ')
        ;;
    *)
        summary=$(echo "$clean" | tr '\n' ' ' | head -c 250)
        ;;
esac

[ -z "$summary" ] && exit 0

# Re-run the meeting guard for summary mode only: the haiku call above takes a
# few seconds, which is long enough to join a call in. The other modes reach
# `say` immediately after Gate 4, so a second probe would only add latency.
if [ "$MODE" = "summary" ]; then
    mic_live && skip "microphone went live while summarizing (${mic_devices:-unknown})"
    [ -f "$HOME/.claude/auto-speak-mute" ] && skip "muted while summarizing"
fi

# Keep a record of the last spoken text + which session it came from
# (for diagnosing any mystery audio)
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') session=${CLAUDE_CODE_SESSION_ID:-?} cwd=${cwd:-?}"
    echo "$summary"
} > /tmp/auto-speak-last.txt

# Apply timbre via Apple's embedded speech command [[pbas N]] (pitch base).
# Honored by the Enhanced/Premium voices; harmless if a voice ignores it.
[ -n "$TIMBRE" ] && summary="[[pbas $TIMBRE]] $summary"

# Speak it in the FOREGROUND. Claude Code kills the hook's process group on exit,
# so backgrounding (even with nohup/disown) gets the speak process SIGKILLed.
# Fall back to the system default voice if the configured one isn't installed.
# (To cut speech short at any time: killall say)
if [ -n "$VOICE" ]; then
    say -v "$VOICE" -r "$RATE" "$summary" </dev/null >/dev/null 2>&1 \
        || say -r "$RATE" "$summary" </dev/null >/dev/null 2>&1
else
    say -r "$RATE" "$summary" </dev/null >/dev/null 2>&1
fi

exit 0