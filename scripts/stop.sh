#!/bin/bash
# Stop auto-speak now: kill the sentence in flight and clear everything queued.
#
# Deliberately self-contained - no imports, no sibling scripts, only stable /tmp
# paths - so a copy of this file keeps working from anywhere: a Keyboard Maestro
# button, a Stream Deck key, an Alfred workflow, a Shortcuts action, or a plain
# terminal. Nothing here needs Claude to be running.
#
# Absolute paths and a hard `exit 0`, because automation shells start with almost
# no PATH and often treat a nonzero exit as a failed action.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

QUEUE_DIR=/tmp/auto-speak-queue
queued=$(ls "$QUEUE_DIR"/*.speak 2>/dev/null | wc -l | tr -d ' ')

# The drainer treats death-by-signal as "stop talking" and purges the backlog
# itself; the rm covers items queued with no drainer alive to notice.
killall say 2>/dev/null
rm -f "$QUEUE_DIR"/*.speak 2>/dev/null

# Only when a Claude session is the caller (the /auto-speak:stop path): silence
# that session's next turn, so a command meaning "be quiet" does not answer out
# loud. A hotkey or button has no turn to suppress and no such variable set.
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    touch "/tmp/auto-speak-skip-next.$CLAUDE_CODE_SESSION_ID" 2>/dev/null
fi

echo "auto-speak stopped; cleared ${queued:-0} queued"
exit 0
