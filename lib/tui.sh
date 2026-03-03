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

  local spinner='|/-\\'
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

sfb_tui_build_display_rows() {
  local entries_file="$1"
  local display_file="$2"

  printf 'SIZE\tTYPE\tRISK\tNAME\tPATH\n' > "$display_file"

  while IFS=$'\t' read -r bytes kind risk_tier _protected path; do
    [ -z "${path:-}" ] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(sfb_human_bytes "$bytes")" "$kind" "$risk_tier" "$(basename "$path")" "$path" >> "$display_file"
  done < "$entries_file"
}

sfb_tui_preview_cmd() {
  cat <<'CMD'
bash -lc '
target="$1"
[ -d "$target" ] || exit 0
printf "Children of %s\n\n" "$target"
printf "%-10s %-4s %s\n" "SIZE" "TYPE" "NAME"
for p in "$target"/*; do
  [ -e "$p" ] || continue
  if [ -d "$p" ]; then
    size="$(du -sh "$p" 2>/dev/null | awk "{print \$1}")"
    printf "%-10s %-4s %s\n" "$size" "dir" "$(basename "$p")"
  elif [ -f "$p" ]; then
    size="$(du -sh "$p" 2>/dev/null | awk "{print \$1}")"
    printf "%-10s %-4s %s\n" "$size" "file" "$(basename "$p")"
  fi
done | head -n 30
' _ {5}
CMD
}

sfb_tui_select_entry() {
  local display_file="$1"
  local prompt="$2"
  local root="$3"

  local cols
  cols="$(tput cols 2>/dev/null || echo 120)"
  local preview_args=()

  if [ "$cols" -ge 110 ]; then
    preview_args=(--preview "$(sfb_tui_preview_cmd)" --preview-window right:55%:wrap)
  fi

  local header
  header="Root: $root"
  if [ -n "$SFB_TUI_STATUS" ]; then
    header="$header\n$SFB_TUI_STATUS"
  fi
  header="$header\nKeys: Enter=open | alt-u=up | alt-m=menu | alt-q=quit"

  awk -F'\t' 'NR==1 { printf "%-10s %-4s %-6s %-28s\t%s\n", $1,$2,$3,$4,$5; next } { printf "%-10s %-4s %-6s %-28s\t%s\n", $1,$2,$3,$4,$5 }' "$display_file" | \
    fzf --ansi --no-hscroll --layout=reverse --border --header "$header" --header-lines=1 \
      --prompt "$prompt > " --expect=alt-u,alt-m,alt-q "${preview_args[@]}"
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

    local result key selected selected_path
    result="$(sfb_tui_select_entry "$display_file" "$prompt_label" "$root")"
    key="$(printf '%s\n' "$result" | sed -n '1p')"
    selected="$(printf '%s\n' "$result" | sed -n '2p')"

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

    [ -z "$selected" ] && {
      printf '__MENU__:%s\n' "$root"
      return 0
    }

    selected_path="$(printf '%s' "$selected" | awk -F'\t' '{print $2}')"

    if [ -d "$selected_path" ]; then
      root="$selected_path"
      sfb_tui_set_status "Opened $root"
    else
      sfb_tui_set_status "Selected file: $selected_path"
    fi
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

  local header
  header="Root: $root"
  if [ -n "$SFB_TUI_STATUS" ]; then
    header="$header\n$SFB_TUI_STATUS"
  fi
  header="$header\nKeys: Enter=inspect | alt-m=menu | alt-q=quit"

  local result key selected
  result="$(awk -F'\t' 'NR==1 { printf "%-10s %-4s %-6s %-28s\t%s\n", $1,$2,$3,$4,$5; next } { printf "%-10s %-4s %-6s %-28s\t%s\n", $1,$2,$3,$4,$5 }' "$display_file" | \
    fzf --ansi --no-hscroll --layout=reverse --border --header "$header" --header-lines=1 \
      --prompt "files > " --expect=alt-m,alt-q)"

  key="$(printf '%s\n' "$result" | sed -n '1p')"
  selected="$(printf '%s\n' "$result" | sed -n '2p')"

  rm -f "$entries_file" "$display_file"

  case "$key" in
    alt-m) printf '__MENU__:%s\n' "$root"; return 0 ;;
    alt-q) printf '__QUIT__:%s\n' "$root"; return 0 ;;
  esac

  if [ -n "$selected" ]; then
    sfb_tui_set_status "Selected file: $(printf '%s' "$selected" | awk -F'\t' '{print $2}')"
  fi

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
          sfb_trash_paths "tui" 0 "" "$target"
          if [ "$?" -eq 0 ]; then
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
  return 0
}
