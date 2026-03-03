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
