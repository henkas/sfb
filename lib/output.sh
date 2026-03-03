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
