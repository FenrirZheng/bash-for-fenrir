#!/usr/bin/env bash
# stop-hook.sh — Auto-save every 15 human messages.
#
# Reads session metadata from stdin (JSON), counts human messages in the
# transcript file, and blocks when the count exceeds the last-saved count
# by 15 or more. State is persisted per session in ~/.mempalace/hook_state/.
#
# Dependencies: jq (preferred) or sed (fallback) for JSON parsing.
# MUST NEVER fail hard — any error outputs {} and exits 0.

main() {
    local THRESHOLD=15
    local STATE_DIR="$HOME/.mempalace/hook_state"
    local input session_id transcript_path stop_hook_active

    # Read hook input from stdin
    input=$(cat)

    # --- Parse fields from JSON ---
    if command -v jq &>/dev/null; then
        session_id=$(echo "$input" | jq -r '.session_id // empty')
        transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
        stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // empty')
    else
        # Fallback: sed-based extraction (portable, no -P flag needed)
        session_id=$(echo "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -1)
        transcript_path=$(echo "$input" | sed -n 's/.*"transcript_path" *: *"\([^"]*\)".*/\1/p' | head -1)
        stop_hook_active=$(echo "$input" | sed -n 's/.*"stop_hook_active" *: *\([a-z]*\).*/\1/p' | head -1)
    fi

    # --- Guards ---

    # Prevent infinite save loops: if the hook itself triggered this stop, bail
    [[ "$stop_hook_active" == "true" ]] && return 0

    # No transcript to count
    [[ -z "$transcript_path" || ! -f "$transcript_path" ]] && return 0

    # No session ID to track state
    [[ -z "$session_id" ]] && return 0

    # Sanitize session_id: only allow safe filename characters
    [[ "$session_id" =~ ^[a-zA-Z0-9._-]+$ ]] || return 0

    # --- Count human messages ---
    local human_count

    # JSONL format (Claude Code transcripts): lines with "role":"human" or "type":"human"
    human_count=$(grep -cE '"role" *: *"human"|"type" *: *"human"' "$transcript_path" 2>/dev/null) || human_count=0

    # Fallback: markdown quote lines (> prefix = user turns)
    if [[ "$human_count" -eq 0 ]]; then
        human_count=$(grep -c '^> ' "$transcript_path" 2>/dev/null) || human_count=0
    fi

    # --- Load last save count ---
    local state_file="$STATE_DIR/${session_id}.last_save"
    local last_save=0
    if [[ -f "$state_file" ]]; then
        last_save=$(cat "$state_file" 2>/dev/null || echo "0")
        [[ "$last_save" =~ ^[0-9]+$ ]] || last_save=0
    fi

    # --- Check threshold ---
    local delta=$((human_count - last_save))

    if [[ "$delta" -ge "$THRESHOLD" ]]; then
        mkdir -p "$STATE_DIR"
        echo "$human_count" > "$state_file"
        cat <<'HOOKJSON'
{
  "continue": false,
  "stopReason": "MemPalace auto-save: 15+ messages since last save. Please review what was discussed and use the mempalace-mine skill to save important conversation context to the palace."
}
HOOKJSON
        exit 0
    fi
}

# Run main; if anything fails, fall through to safe default
main 2>/dev/null || true
echo "{}"
