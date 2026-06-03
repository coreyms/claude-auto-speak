#!/bin/bash

# First-run nudge: if auto-speak has never been configured on this machine,
# tell Claude (via SessionStart stdout -> context) to offer the setup walkthrough.
# Stays silent once ~/.claude/auto-speak.conf exists.

[ -f "$HOME/.claude/auto-speak.conf" ] && exit 0

cat <<'EOF'
The auto-speak plugin is installed but not yet configured on this machine
(no ~/.claude/auto-speak.conf). Responses are spoken with the system default
voice until setup runs. Briefly let the user know and offer to run
/auto-speak:setup to pick a voice, speech rate, and how much of each response
to read aloud. Mention this once, then drop it unless asked.
EOF
exit 0