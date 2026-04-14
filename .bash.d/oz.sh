_oz_path_regex='[\w./-]+\.(?:java|kt|xml|yaml|yml|json|md|rs|py|ts|tsx|js|jsx|go|sh|proto|tf|toml|gradle)(?::\d+)?'

oz() {
  tmux capture-pane -p -S -50 \
    | grep -oP "$_oz_path_regex" \
    | sort -u \
    | fzf --height=40% --reverse --prompt="Zed 開啟 > " \
    | xargs -r zed
}

# oz-claude: extract paths from the newest Claude Code session transcript for $PWD
ozc() {
  local proj="${HOME}/.claude/projects/${PWD//\//-}"
  local session
  session=$(ls -t "$proj"/*.jsonl 2>/dev/null | head -1)
  if [[ -z "$session" ]]; then
    echo "ozc: no Claude Code session found under $proj" >&2
    return 1
  fi
  grep -oP "$_oz_path_regex" "$session" \
    | sort -u \
    | fzf --height=40% --reverse --prompt="Zed 開啟 (claude) > " \
    | xargs -r zed
}
