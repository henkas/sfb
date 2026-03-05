#!/usr/bin/env bash

sfb_kib_to_bytes() {
  local kib="$1"
  printf '%s\n' "$((kib * 1024))"
}

sfb_scan_directories() {
  local root="$1"
  local depth="$2"
  local top_n="$3"
  local entries_file="$4"

  local tmp
  tmp="$(mktemp)"
  sfb_prepare_classification_context

  while IFS= read -r -d '' dir; do
    local kib bytes
    kib="$(du -sk "$dir" 2>/dev/null | awk '{print $1}')"
    [ -z "$kib" ] && continue
    bytes="$(sfb_kib_to_bytes "$kib")"

    sfb_classify_path "$dir"
    printf '%s\tdir\t%s\t%s\t%s\n' \
      "$bytes" "$SFB_PATH_TIER" "$SFB_PATH_PROTECTED" "$SFB_PATH_CANONICAL" >> "$tmp"
  done < <(find "$root" -mindepth 1 -maxdepth "$depth" -type d -print0 2>/dev/null)

  sort -nr -k1,1 "$tmp" | head -n "$top_n" > "$entries_file"
  rm -f "$tmp"
}

sfb_scan_top_level_directories() {
  local root="$1"
  local top_n="$2"
  local entries_file="$3"

  local tmp
  tmp="$(mktemp)"
  sfb_prepare_classification_context

  while IFS= read -r -d '' dir; do
    local kib bytes
    kib="$(du -sk "$dir" 2>/dev/null | awk '{print $1}')"
    [ -z "$kib" ] && continue
    bytes="$(sfb_kib_to_bytes "$kib")"

    sfb_classify_path "$dir"
    printf '%s\tdir\t%s\t%s\t%s\n' \
      "$bytes" "$SFB_PATH_TIER" "$SFB_PATH_PROTECTED" "$SFB_PATH_CANONICAL" >> "$tmp"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  sort -nr -k1,1 "$tmp" | head -n "$top_n" > "$entries_file"
  rm -f "$tmp"
}

sfb_list_immediate_children() {
  local root="$1"
  local top_n="$2"
  local entries_file="$3"

  local tmp
  tmp="$(mktemp)"
  sfb_prepare_classification_context

  while IFS= read -r -d '' item; do
    local bytes kind kib
    if [ -d "$item" ]; then
      kind="dir"
      kib="$(du -sk "$item" 2>/dev/null | awk '{print $1}')"
      [ -z "$kib" ] && continue
      bytes="$(sfb_kib_to_bytes "$kib")"
    elif [ -f "$item" ]; then
      kind="file"
      bytes="$(stat -f '%z' "$item" 2>/dev/null)"
      [ -z "$bytes" ] && continue
    else
      continue
    fi

    sfb_classify_path "$item"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$bytes" "$kind" "$SFB_PATH_TIER" "$SFB_PATH_PROTECTED" "$SFB_PATH_CANONICAL" >> "$tmp"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

  sort -nr -k1,1 "$tmp" | head -n "$top_n" > "$entries_file"
  rm -f "$tmp"
}

sfb_scan_largest_files() {
  local root="$1"
  local top_n="$2"
  local entries_file="$3"

  local tmp
  tmp="$(mktemp)"
  sfb_prepare_classification_context

  find "$root" -type f -exec stat -f '%z\t%N' {} + 2>/dev/null | sort -nr -k1,1 | head -n "$top_n" | \
    while IFS=$'\t' read -r bytes path; do
      [ -z "${path:-}" ] && continue
      sfb_classify_path "$path"
      printf '%s\tfile\t%s\t%s\t%s\n' \
        "$bytes" "$SFB_PATH_TIER" "$SFB_PATH_PROTECTED" "$SFB_PATH_CANONICAL" >> "$tmp"
    done

  cat "$tmp" > "$entries_file"
  rm -f "$tmp"
}

sfb_collect_summary_entries() {
  local root="$1"
  local top_entries_file="$2"
  local extension_file="$3"
  local stats_file="$4"

  local tmp
  tmp="$(mktemp)"

  find "$root" -type f -exec stat -f '%z\t%N' {} + 2>/dev/null | \
    while IFS=$'\t' read -r bytes file; do
      local name ext
      [ -n "${bytes:-}" ] || continue
      [ -n "${file:-}" ] || continue

      name="$(basename "$file")"
      ext="(none)"
      if [[ "$name" == *.* && "$name" != .* ]]; then
        ext="$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')"
      fi

      printf '%s\t%s\t%s\n' "$bytes" "$file" "$ext" >> "$tmp"
    done

  if [ ! -s "$tmp" ]; then
    : > "$top_entries_file"
    : > "$extension_file"
    printf '0\t0\n' > "$stats_file"
    rm -f "$tmp"
    return 0
  fi

  sort -nr -k1,1 "$tmp" | head -n 10 > "$top_entries_file"

  awk -F'\t' '
    {
      ext = $3
      count[ext] += 1
      bytes[ext] += $1
    }
    END {
      for (ext in count) {
        printf "%s\t%s\t%s\n", bytes[ext], count[ext], ext
      }
    }
  ' "$tmp" | sort -nr -k1,1 > "$extension_file"

  awk -F'\t' '
    { total += $1; count += 1 }
    END { printf "%s\t%s\n", total + 0, count + 0 }
  ' "$tmp" > "$stats_file"

  rm -f "$tmp"
}

sfb_find_entries() {
  local root="$1"
  local name_pattern="$2"
  local entries_file="$3"

  local tmp
  tmp="$(mktemp)"
  sfb_prepare_classification_context

  sfb_classify_path "$root"
  if [ "$SFB_PATH_BLOCKED" -eq 1 ]; then
    rm -f "$tmp"
    return 3
  fi

  local path rel bytes kind
  if command -v fd >/dev/null 2>&1; then
    while IFS= read -r -d '' rel; do
      [ -n "${rel:-}" ] || continue
      path="$root/$rel"
      [ -e "$path" ] || continue

      if [ -d "$path" ]; then
        kind="dir"
        bytes=0
      elif [ -f "$path" ]; then
        kind="file"
        bytes="$(stat -f '%z' "$path" 2>/dev/null)"
        [ -n "${bytes:-}" ] || continue
      else
        continue
      fi

      sfb_classify_path "$path"
      [ "$SFB_PATH_BLOCKED" -eq 1 ] && continue

      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$bytes" "$kind" "$SFB_PATH_TIER" "$SFB_PATH_PROTECTED" "$SFB_PATH_CANONICAL" >> "$tmp"
    done < <(
      cd "$root" 2>/dev/null || exit 1
      if [ -n "$name_pattern" ]; then
        fd -0 --color never --strip-cwd-prefix --glob "$name_pattern"
      else
        fd -0 --color never --strip-cwd-prefix
      fi
    )
  else
    while IFS= read -r -d '' path; do
      [ -e "$path" ] || continue

      if [ -d "$path" ]; then
        kind="dir"
        bytes=0
      elif [ -f "$path" ]; then
        kind="file"
        bytes="$(stat -f '%z' "$path" 2>/dev/null)"
        [ -n "${bytes:-}" ] || continue
      else
        continue
      fi

      sfb_classify_path "$path"
      [ "$SFB_PATH_BLOCKED" -eq 1 ] && continue

      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$bytes" "$kind" "$SFB_PATH_TIER" "$SFB_PATH_PROTECTED" "$SFB_PATH_CANONICAL" >> "$tmp"
    done < <(
      if [ -n "$name_pattern" ]; then
        find "$root" -mindepth 1 \
          \( -type d -name '.*' -prune \) -o \
          \( ! -name '.*' -name "$name_pattern" -print0 \) 2>/dev/null
      else
        find "$root" -mindepth 1 \
          \( -type d -name '.*' -prune \) -o \
          \( ! -name '.*' -print0 \) 2>/dev/null
      fi
    )
  fi

  sort -nr -k1,1 "$tmp" > "$entries_file"
  rm -f "$tmp"
}
