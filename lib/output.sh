#!/usr/bin/env bash

sfb_json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    NR > 1 { printf "\\n" }
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\t/,"\\t")
      gsub(/\r/,"\\r")
      printf "%s", $0
    }
  '
}

sfb_human_bytes() {
  local bytes="${1:-0}"
  local units=("B" "KB" "MB" "GB" "TB" "PB")
  local idx=0
  local whole="$bytes"

  while [ "$whole" -ge 1024 ] && [ "$idx" -lt 5 ]; do
    whole=$((whole / 1024))
    idx=$((idx + 1))
  done

  printf '%s%s' "$whole" "${units[$idx]}"
}

sfb_print_entries_tsv() {
  local entries_file="$1"
  printf 'bytes\tkind\trisk_tier\tprotected\tpath\n'
  cat "$entries_file"
}

sfb_print_entries_json() {
  local root="$1"
  local entries_file="$2"
  local version="0.1.0"
  local generated_at
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  printf '{'
  printf '"version":"%s",' "$(sfb_json_escape "$version")"
  printf '"root":"%s",' "$(sfb_json_escape "$root")"
  printf '"generated_at":"%s",' "$(sfb_json_escape "$generated_at")"
  printf '"entries":['

  local first=1
  while IFS=$'\t' read -r bytes kind risk_tier protected path; do
    [ -z "${path:-}" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{'
    printf '"path":"%s",' "$(sfb_json_escape "$path")"
    printf '"name":"%s",' "$(sfb_json_escape "$(basename "$path")")"
    printf '"bytes":%s,' "$bytes"
    printf '"kind":"%s",' "$(sfb_json_escape "$kind")"
    printf '"risk_tier":"%s",' "$(sfb_json_escape "$risk_tier")"
    printf '"protected":%s' "$protected"
    printf '}'
  done < "$entries_file"

  printf ']}'
  printf '\n'
}

sfb_print_doctor_json() {
  local missing_csv="$1"
  local installed_csv="$2"

  printf '{"ok":%s,' "$([ -z "$missing_csv" ] && echo true || echo false)"
  printf '"missing":['
  local first=1
  IFS=',' read -r -a missing_arr <<< "$missing_csv"
  local item
  for item in "${missing_arr[@]}"; do
    [ -z "$item" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '"%s"' "$(sfb_json_escape "$item")"
  done
  printf '],"installed":['
  first=1
  IFS=',' read -r -a installed_arr <<< "$installed_csv"
  for item in "${installed_arr[@]}"; do
    [ -z "$item" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '"%s"' "$(sfb_json_escape "$item")"
  done
  printf ']}'
  printf '\n'
}

sfb_print_trash_json() {
  local requested_csv="$1"
  local trashed_csv="$2"
  local blocked_file="$3"
  local requires_human_confirmation="$4"
  local exit_code="$5"

  printf '{'
  printf '"requested":['
  local first=1
  IFS='|' read -r -a requested_arr <<< "$requested_csv"
  local item
  for item in "${requested_arr[@]}"; do
    [ -z "$item" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '"%s"' "$(sfb_json_escape "$item")"
  done

  printf '],"trashed":['
  first=1
  IFS='|' read -r -a trashed_arr <<< "$trashed_csv"
  for item in "${trashed_arr[@]}"; do
    [ -z "$item" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '"%s"' "$(sfb_json_escape "$item")"
  done

  printf '],"blocked":['
  first=1
  while IFS=$'\t' read -r path reason tier; do
    [ -z "${path:-}" ] && continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{"path":"%s","reason":"%s","risk_tier":"%s"}' \
      "$(sfb_json_escape "$path")" "$(sfb_json_escape "$reason")" "$(sfb_json_escape "$tier")"
  done < "$blocked_file"

  printf '],"requires_human_confirmation":%s,' "$requires_human_confirmation"
  printf '"exit_code":%s' "$exit_code"
  printf '}'
  printf '\n'
}

sfb_print_summary_text() {
  local root="$1"
  local total_bytes="$2"
  local file_count="$3"
  local top_entries_file="$4"
  local extension_file="$5"

  printf 'Root: %s\n' "$root"
  printf 'Total size: %s (%s bytes)\n' "$(sfb_human_bytes "$total_bytes")" "$total_bytes"
  printf 'File count: %s\n' "$file_count"
  printf '\n'

  printf 'Top 10 by size:\n'
  printf '%12s  %-10s  %s\n' "BYTES" "SIZE" "PATH"
  while IFS=$'\t' read -r bytes path _ext; do
    [ -n "${path:-}" ] || continue
    printf '%12s  %-10s  %s\n' "$bytes" "$(sfb_human_bytes "$bytes")" "$path"
  done < "$top_entries_file"
  printf '\n'

  printf 'Extension breakdown:\n'
  printf '%-12s  %8s  %12s  %-10s\n' "EXTENSION" "COUNT" "BYTES" "SIZE"
  while IFS=$'\t' read -r ext_bytes ext_count extension; do
    [ -n "${extension:-}" ] || continue
    printf '%-12s  %8s  %12s  %-10s\n' \
      "$extension" "$ext_count" "$ext_bytes" "$(sfb_human_bytes "$ext_bytes")"
  done < "$extension_file"
}

sfb_print_summary_json() {
  local root="$1"
  local total_bytes="$2"
  local file_count="$3"
  local top_entries_file="$4"
  local extension_file="$5"
  local version="0.1.0"
  local generated_at
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  printf '{'
  printf '"version":"%s",' "$(sfb_json_escape "$version")"
  printf '"root":"%s",' "$(sfb_json_escape "$root")"
  printf '"generated_at":"%s",' "$(sfb_json_escape "$generated_at")"
  printf '"summary":{'
  printf '"total_bytes":%s,' "$total_bytes"
  printf '"file_count":%s,' "$file_count"

  printf '"top_by_size":['
  local first=1
  local bytes path
  while IFS=$'\t' read -r bytes path _ext; do
    [ -n "${path:-}" ] || continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{'
    printf '"path":"%s",' "$(sfb_json_escape "$path")"
    printf '"name":"%s",' "$(sfb_json_escape "$(basename "$path")")"
    printf '"bytes":%s' "$bytes"
    printf '}'
  done < "$top_entries_file"
  printf '],'

  printf '"extensions":['
  first=1
  local ext_bytes ext_count extension
  while IFS=$'\t' read -r ext_bytes ext_count extension; do
    [ -n "${extension:-}" ] || continue
    [ "$first" -eq 0 ] && printf ','
    first=0
    printf '{'
    printf '"extension":"%s",' "$(sfb_json_escape "$extension")"
    printf '"count":%s,' "$ext_count"
    printf '"total_bytes":%s' "$ext_bytes"
    printf '}'
  done < "$extension_file"
  printf ']'

  printf '}}'
  printf '\n'
}
