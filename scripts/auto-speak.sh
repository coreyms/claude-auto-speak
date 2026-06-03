#!/bin/bash

# Auto-speak hook for Claude Code
# Speaks Claude's response after each turn (Stop hook)
# Uses macOS built-in `say` (local, free) - no OpenAI API involved.

# Defaults - override per machine in ~/.claude/auto-speak.conf (run /auto-speak:setup)
VOICE=""            # empty = system default voice; or any name from `say -v '?'`
RATE=210            # words per minute; macOS default is ~175
MODE="paragraph"    # sentence | paragraph | full | summary

CONF="$HOME/.claude/auto-speak.conf"
[ -f "$CONF" ] && . "$CONF"

# Ensure homebrew tools (jq) and the claude CLI are findable even if the hook
# env has a minimal PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

json=$(cat)

# Skip headless/background sessions (e.g. the remember plugin runs `claude -p`
# from /tmp to write memory notes - without this, the hook reads those aloud).
# User-scoped Stop hooks fire for EVERY claude session, not just interactive ones.
cwd=$(echo "$json" | jq -r '.cwd // ""' 2>/dev/null)
case "$cwd" in
    /tmp|/tmp/*|/private/tmp|/private/tmp/*) exit 0 ;;
esac

# Claude Code sends the response text as last_assistant_message
msg=$(echo "$json" | jq -r '.last_assistant_message // ""' 2>/dev/null)

# Skip if empty or too short
[ -z "$msg" ] || [ ${#msg} -lt 30 ] && exit 0

# Strip markdown that reads badly aloud: fenced code blocks, inline backticks,
# bold/italic markers, heading hashes, link targets (keep link text)
clean=$(echo "$msg" | sed -E '/^```/,/^```/d' | sed -E '
    s/`([^`]*)`/\1/g
    s/\*\*([^*]*)\*\*/\1/g
    s/\*([^*]*)\*/\1/g
    s/^#+ //
    s/\[([^]]*)\]\([^)]*\)/\1/g
')

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
                "Condense this assistant response into one to three short conversational sentences to be spoken aloud to the user. Lead with the bottom line. If the response asks the user any questions or needs a decision, you MUST include that. Output ONLY the text to speak - no preamble, no markdown.") \
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

# Keep a record of the last spoken text (for diagnosing any mystery audio)
echo "$summary" > /tmp/auto-speak-last.txt

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