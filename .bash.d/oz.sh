oz() {
  tmux capture-pane -p -S -50 \
    | grep -oP '[\w./-]+\.(?:java|kt|xml|yaml|yml|json|md|rs|py|ts|js)(?::\d+)?' \
    | sort -u \
    | fzf --height=40% --reverse --prompt="Zed 開啟 > " \
    | xargs -r zed
}
