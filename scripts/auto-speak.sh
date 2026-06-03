#!/bin/bash

# Auto-speak hook for Claude Code
# Speaks Claude's response after each turn (Stop hook)
# Uses macOS built-in `say` (local, free) - no OpenAI API involved.

VOICE="Tom (Enhanced)"
RATE=210            # words per minute; macOS default is ~175
MODE="paragraph"    # sentence | paragraph | full

# Ensure homebrew tools (jq) are findable even if the hook env has a minimal PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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
    *)
        summary=$(echo "$clean" | tr '\n' ' ' | head -c 250)
        ;;
esac

[ -z "$summary" ] && exit 0

# Keep a record of the last spoken text (for diagnosing any mystery audio)
echo "$summary" > /tmp/auto-speak-last.txt

# Speak it in the FOREGROUND. Claude Code kills the hook's process group on exit,
# so backgrounding (even with nohup/disown) gets the speak process SIGKILLed.
# (To cut speech short at any time: killall say)
say -v "$VOICE" -r "$RATE" "$summary" </dev/null >/dev/null 2>&1

exit 0