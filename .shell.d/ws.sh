ws() {
  local arg="$1" file line
  if [[ "$arg" == *:* ]]; then
    file="${arg%:*}"
    line="${arg##*:}"
    webstorm --line "$line" "$file"
  else
    webstorm "$arg"
  fi
}
