#!/usr/bin/env bash

SFB_TUI_STATUS=""

sfb_tui_cleanup() {
  tput cnorm 2>/dev/null || true
  tput rmcup 2>/dev/null || true
}

sfb_tui_set_status() {
  SFB_TUI_STATUS="$1"
}

sfb_tui_run_with_spinner() {
  local message="$1"
  shift

  local log_file
  log_file="$(mktemp)"

  "$@" >"$log_file" 2>&1 &
  local pid=$!

  local spinner="|/-\\"
  local idx=0

  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s %s' "$message" "${spinner:$((idx % 4)):1}"
    idx=$((idx + 1))
    sleep 0.08
  done

  wait "$pid"
  local rc=$?
  printf '\r\033[K'

  if [ "$rc" -ne 0 ]; then
    local preview
    preview="$(sed -n '1,3p' "$log_file" | tr '\n' '; ')"
    sfb_tui_set_status "Error: ${preview:-scan failed}"
  fi

  rm -f "$log_file"
  return "$rc"
}

sfb_tui_size_bar() {
  local bytes="${1:-0}"
  local max_bytes="${2:-0}"
  local width=10
  local filled=0

  if [ "$max_bytes" -gt 0 ] && [ "$bytes" -gt 0 ]; then
    filled=$((bytes * width / max_bytes))
    [ "$filled" -lt 1 ] && filled=1
    [ "$filled" -gt "$width" ] && filled="$width"
  fi

  local i
  local bar=""
  for ((i = 0; i < filled; i++)); do
    bar="${bar}█"
  done
  for ((i = filled; i < width; i++)); do
    bar="${bar}░"
  done

  printf '%s' "$bar"
}

sfb_tui_build_display_rows() {
  local entries_file="$1"
  local display_file="$2"

  printf 'SIZE       BAR        TYPE RISK   NAME\tPATH\n' > "$display_file"

  local max_bytes
  max_bytes="$(awk -F'\t' 'BEGIN { m=0 } { if ($1 > m) m = $1 } END { print m + 0 }' "$entries_file")"

  while IFS=$'\t' read -r bytes kind risk_tier _protected path; do
    [ -z "${path:-}" ] && continue

    local size bar display
    size="$(sfb_human_bytes "$bytes")"
    bar="$(sfb_tui_size_bar "$bytes" "$max_bytes")"
    display="$(printf '%-10s %-10s %-4s %-6s %-28s' "$size" "$bar" "$kind" "$risk_tier" "$(basename "$path")")"

    printf '%s\t%s\n' "$display" "$path" >> "$display_file"
  done < "$entries_file"
}

sfb_tui_preview_cmd() {
  cat <<'CMD'
bash -lc '
target="$1"
[ -n "$target" ] || exit 0

if [ -f "$target" ]; then
  printf "File: %s\n\n" "$target"
  if command -v bat >/dev/null 2>&1; then
    bat --style=plain --color=always --line-range=:200 -- "$target"
  else
    sed -n "1,200p" "$target"
  fi
  exit 0
fi

if [ -d "$target" ]; then
  printf "Directory: %s\n" "$target"
  printf "Total: %s\n\n" "$(du -sh "$target" 2>/dev/null | awk "{print \$1}")"
  printf "%-10s %s\n" "SIZE" "CHILD"
  find "$target" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | \
    while IFS= read -r -d "" p; do
      size="$(du -sh "$p" 2>/dev/null | awk "{print \$1}")"
      [ -n "$size" ] || continue
      printf "%s\t%s\n" "$size" "$(basename "$p")"
    done | sort -hr -k1,1 | head -n 30 | awk -F"\t" "{ printf \"%-10s %s\\n\", \$1, \$2 }"
  exit 0
fi

printf "Path unavailable: %s\n" "$target"
' _ {2}
CMD
}

sfb_tui_select_entry() {
  local display_file="$1"
  local prompt="$2"
  local root="$3"
  local help_line="$4"
  local expect_keys="$5"

  local cols
  cols="$(tput cols 2>/dev/null || echo 120)"
  local preview_window='right:55%:wrap'
  if [ "$cols" -lt 110 ]; then
    preview_window='down:45%:wrap'
  fi

  local header
  header="Root: $root"
  if [ -n "$SFB_TUI_STATUS" ]; then
    header="$header\n$SFB_TUI_STATUS"
  fi
  header="$header\n$help_line"

  fzf --ansi --layout=reverse --border --header "$header" --header-lines=1 \
    --prompt "$prompt > " --expect="$expect_keys" --multi --delimiter=$'\t' --with-nth=1 \
    --preview "$(sfb_tui_preview_cmd)" --preview-window "$preview_window" \
    --bind '?:toggle-preview' < "$display_file"
}

sfb_tui_extract_selected_paths() {
  local result="$1"
  printf '%s\n' "$result" | sed -n '2,$p' | awk -F'\t' 'NF >= 2 { print $2 }'
}

sfb_tui_open_paths() {
  local mode="$1"
  shift
  local paths=("$@")
  local path

  for path in "${paths[@]}"; do
    if [ "$mode" = "reveal" ]; then
      open -R "$path"
    else
      open "$path"
    fi
  done
}

sfb_tui_browse_loop() {
  local root="$1"
  local dirs_only="$2"
  local prompt_label="$3"
  local top_n=200

  while true; do
    local entries_file display_file
    entries_file="$(mktemp)"
    display_file="$(mktemp)"

    if [ "$dirs_only" -eq 1 ]; then
      sfb_tui_run_with_spinner "Scanning directories" sfb_scan_top_level_directories "$root" "$top_n" "$entries_file" || {
        rm -f "$entries_file" "$display_file"
        return 1
      }
    else
      sfb_tui_run_with_spinner "Loading entries" sfb_list_immediate_children "$root" "$top_n" "$entries_file" || {
        rm -f "$entries_file" "$display_file"
        return 1
      }
    fi

    sfb_tui_build_display_rows "$entries_file" "$display_file"

    if [ "$(wc -l < "$display_file")" -le 1 ]; then
      sfb_tui_set_status "No entries under $root"
      rm -f "$entries_file" "$display_file"
      return 0
    fi

    local help_line result key
    help_line='Keys: Enter=confirm | Tab=select | d=descend | o=open | r=reveal | t=trash | ?=preview | alt-u=up | alt-m=menu | alt-q=quit'
    result="$(sfb_tui_select_entry "$display_file" "$prompt_label" "$root" "$help_line" 'alt-u,alt-m,alt-q,o,r,t,d')"
    key="$(printf '%s\n' "$result" | sed -n '1p')"

    local selected_paths=()
    mapfile -t selected_paths < <(sfb_tui_extract_selected_paths "$result")

    rm -f "$entries_file" "$display_file"

    case "$key" in
      alt-u)
        if [ "$root" != "/" ]; then
          root="$(dirname "$root")"
          sfb_tui_set_status "Moved up to $root"
        fi
        continue
        ;;
      alt-m)
        printf '__MENU__:%s\n' "$root"
        return 0
        ;;
      alt-q)
        printf '__QUIT__:%s\n' "$root"
        return 0
        ;;
    esac

    if [ "${#selected_paths[@]}" -eq 0 ]; then
      printf '__MENU__:%s\n' "$root"
      return 0
    fi

    case "$key" in
      o)
        if sfb_tui_open_paths "open" "${selected_paths[@]}"; then
          sfb_tui_set_status "Opened ${#selected_paths[@]} item(s)"
        else
          sfb_tui_set_status "Open action failed"
        fi
        continue
        ;;
      r)
        if sfb_tui_open_paths "reveal" "${selected_paths[@]}"; then
          sfb_tui_set_status "Revealed ${#selected_paths[@]} item(s) in Finder"
        else
          sfb_tui_set_status "Reveal action failed"
        fi
        continue
        ;;
      t)
        if sfb_trash_paths "tui" 0 "" "${selected_paths[@]}"; then
          sfb_tui_set_status "Moved ${#selected_paths[@]} item(s) to Trash"
        else
          sfb_tui_set_status "Trash action did not fully complete"
        fi
        continue
        ;;
      d)
        if [ "${#selected_paths[@]}" -ne 1 ]; then
          sfb_tui_set_status "Descend requires exactly one selected directory"
          continue
        fi
        if [ -d "${selected_paths[0]}" ]; then
          root="${selected_paths[0]}"
          sfb_tui_set_status "Opened $root"
        else
          sfb_tui_set_status "Descend requires a directory"
        fi
        continue
        ;;
      "")
        sfb_tui_set_status "Selected ${#selected_paths[@]} item(s)"
        continue
        ;;
      *)
        sfb_tui_set_status "Unhandled key: $key"
        continue
        ;;
    esac
  done
}

sfb_tui_largest_files() {
  local root="$1"
  local top_n=200
  local entries_file display_file
  entries_file="$(mktemp)"
  display_file="$(mktemp)"

  sfb_tui_run_with_spinner "Scanning files" sfb_scan_largest_files "$root" "$top_n" "$entries_file" || {
    rm -f "$entries_file" "$display_file"
    return 1
  }

  sfb_tui_build_display_rows "$entries_file" "$display_file"
  if [ "$(wc -l < "$display_file")" -le 1 ]; then
    sfb_tui_set_status "No files found under $root"
    rm -f "$entries_file" "$display_file"
    return 0
  fi

  local help_line result key
  help_line='Keys: Enter=confirm | Tab=select | o=open | r=reveal | t=trash | ?=preview | alt-m=menu | alt-q=quit'
  result="$(sfb_tui_select_entry "$display_file" "files" "$root" "$help_line" 'alt-m,alt-q,o,r,t')"
  key="$(printf '%s\n' "$result" | sed -n '1p')"

  local selected_paths=()
  mapfile -t selected_paths < <(sfb_tui_extract_selected_paths "$result")

  rm -f "$entries_file" "$display_file"

  case "$key" in
    alt-m)
      printf '__MENU__:%s\n' "$root"
      return 0
      ;;
    alt-q)
      printf '__QUIT__:%s\n' "$root"
      return 0
      ;;
  esac

  if [ "${#selected_paths[@]}" -eq 0 ]; then
    printf '__MENU__:%s\n' "$root"
    return 0
  fi

  case "$key" in
    o)
      if sfb_tui_open_paths "open" "${selected_paths[@]}"; then
        sfb_tui_set_status "Opened ${#selected_paths[@]} file(s)"
      else
        sfb_tui_set_status "Open action failed"
      fi
      ;;
    r)
      if sfb_tui_open_paths "reveal" "${selected_paths[@]}"; then
        sfb_tui_set_status "Revealed ${#selected_paths[@]} file(s) in Finder"
      else
        sfb_tui_set_status "Reveal action failed"
      fi
      ;;
    t)
      if sfb_trash_paths "tui" 0 "" "${selected_paths[@]}"; then
        sfb_tui_set_status "Moved ${#selected_paths[@]} file(s) to Trash"
      else
        sfb_tui_set_status "Trash action did not fully complete"
      fi
      ;;
    "")
      sfb_tui_set_status "Selected ${#selected_paths[@]} file(s)"
      ;;
    *)
      sfb_tui_set_status "Unhandled key: $key"
      ;;
  esac

  printf '__MENU__:%s\n' "$root"
}

sfb_tui_menu() {
  local root="$1"

  local header
  header="Root: $root"
  if [ -n "$SFB_TUI_STATUS" ]; then
    header="$header\n$SFB_TUI_STATUS"
  fi
  header="$header\nMenu: choose an action"

  printf '%s\n' \
    "Browse files" \
    "Largest directories" \
    "Largest files" \
    "Trash path" \
    "Change root" \
    "Refresh" \
    "Quit" | \
    fzf --layout=reverse --border --prompt "sfb > " --header "$header"
}

sfb_tui() {
  local root="$1"

  if ! command -v fzf >/dev/null 2>&1; then
    printf 'fzf is required for TUI mode. Run: sfb doctor --install-deps\n' >&2
    return 4
  fi

  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  trap 'sfb_tui_cleanup' INT TERM EXIT

  while true; do
    local action
    action="$(sfb_tui_menu "$root")"

    [ -z "$action" ] && break

    case "$action" in
      "Browse files")
        local browse_result browse_cmd
        if ! browse_result="$(sfb_tui_browse_loop "$root" 0 "browse")"; then
          sfb_tui_set_status "Browse failed for $root"
          continue
        fi
        browse_cmd="${browse_result%%:*}"
        root="${browse_result#*:}"
        [ "$browse_cmd" = "__QUIT__" ] && break
        ;;
      "Largest directories")
        local dir_result dir_cmd
        if ! dir_result="$(sfb_tui_browse_loop "$root" 1 "dirs")"; then
          sfb_tui_set_status "Directory scan failed for $root"
          continue
        fi
        dir_cmd="${dir_result%%:*}"
        root="${dir_result#*:}"
        [ "$dir_cmd" = "__QUIT__" ] && break
        ;;
      "Largest files")
        local files_result files_cmd
        if ! files_result="$(sfb_tui_largest_files "$root")"; then
          sfb_tui_set_status "File scan failed for $root"
          continue
        fi
        files_cmd="${files_result%%:*}"
        root="${files_result#*:}"
        [ "$files_cmd" = "__QUIT__" ] && break
        ;;
      "Trash path")
        printf 'Path to trash (absolute or relative): '
        local target
        read -r target
        if [ -n "$target" ]; then
          if sfb_trash_paths "tui" 0 "" "$target"; then
            sfb_tui_set_status "Moved to Trash: $target"
          else
            sfb_tui_set_status "Trash action did not complete: $target"
          fi
        fi
        ;;
      "Change root")
        printf 'New root path: '
        local new_root
        read -r new_root
        if [ -n "$new_root" ]; then
          if [ -d "$new_root" ]; then
            root="$(sfb_abspath "$new_root")"
            sfb_tui_set_status "Root changed to $root"
          else
            sfb_tui_set_status "Not a directory: $new_root"
          fi
        fi
        ;;
      "Refresh")
        sfb_tui_set_status "Refreshed"
        ;;
      "Quit")
        break
        ;;
    esac
  done

  sfb_tui_cleanup
  trap - INT TERM EXIT
}
