#!/usr/bin/env bash
# precompact-hook.sh — Emergency save before context compaction.
# Always blocks to give the model a chance to save palace state.
# This is unconditional: compaction permanently loses detailed context.

# Consume stdin (required by hook protocol)
cat > /dev/null

cat <<'EOF'
{
  "continue": false,
  "stopReason": "MemPalace pre-compact save: Context is about to be compacted. Please review the conversation and use the mempalace-mine skill to save important context to the palace before compaction proceeds."
}
EOF
