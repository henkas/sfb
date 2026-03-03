#!/usr/bin/env bash

SFB_CONFIG_FILE="${SFB_CONFIG_FILE:-$HOME/.config/sfb/config}"
SFB_TOKEN_FILE="${SFB_TOKEN_FILE:-$HOME/.cache/sfb/session}"

SFB_ALLOW_HIGH_RISK_DELETE=0
SFB_TOKEN_TTL_SECONDS=600
SFB_EXTRA_PROTECTED_PATHS=""
SFB_UNPROTECTED_PATHS=""

SFB_HARD_PROTECTED=("/" "/System" "/usr" "/bin" "/sbin" "/private" "/dev" "/etc" "/var/db")
SFB_HOME_CRITICAL=("$HOME/Library" "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.config" "$HOME/.local/share")
SFB_EXTRA_PROTECTED=()
SFB_UNPROTECTED=()
SFB_CLASSIFICATION_READY=0
# shellcheck disable=SC2034
SFB_PATH_CANONICAL=""
# shellcheck disable=SC2034
SFB_PATH_TIER="low"
# shellcheck disable=SC2034
SFB_PATH_PROTECTED=false
# shellcheck disable=SC2034
SFB_PATH_BLOCKED=0
# shellcheck disable=SC2034
SFB_PATH_REASON="normal"
# shellcheck disable=SC2034
SFB_TOKEN_VALIDATION_ERROR=""

sfb_select_state_paths() {
  local config_dir token_dir

  config_dir="$(dirname "$SFB_CONFIG_FILE")"
  if ! mkdir -p "$config_dir" 2>/dev/null; then
    SFB_CONFIG_FILE="${TMPDIR:-/tmp}/sfb/config"
    config_dir="$(dirname "$SFB_CONFIG_FILE")"
    mkdir -p "$config_dir"
  fi

  token_dir="$(dirname "$SFB_TOKEN_FILE")"
  if ! mkdir -p "$token_dir" 2>/dev/null; then
    SFB_TOKEN_FILE="${TMPDIR:-/tmp}/sfb/session"
    token_dir="$(dirname "$SFB_TOKEN_FILE")"
    mkdir -p "$token_dir"
  fi
}

sfb_expand_home() {
  local path="$1"
  if [ "$path" = "~" ]; then
    printf '%s\n' "$HOME"
    return 0
  fi
  if [ "${path#~/}" != "$path" ]; then
    printf '%s/%s\n' "$HOME" "${path#~/}"
    return 0
  fi
  printf '%s\n' "$path"
}

sfb_abspath() {
  local input
  input="$(sfb_expand_home "$1")"
  local abs

  if [ -d "$input" ]; then
    (cd "$input" 2>/dev/null && pwd -P)
    return $?
  fi

  if [ -e "$input" ]; then
    local dir base
    dir="$(dirname "$input")"
    base="$(basename "$input")"
    abs="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$abs" "$base"
    return 0
  fi

  local dir base
  dir="$(dirname "$input")"
  base="$(basename "$input")"
  if [ "$dir" = "." ]; then
    printf '%s/%s\n' "$(pwd -P)" "$base"
    return 0
  fi

  if [ -d "$dir" ]; then
    abs="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$abs" "$base"
    return 0
  fi

  return 1
}

sfb_path_is_under() {
  local target="$1"
  local prefix="$2"

  [ -z "$prefix" ] && return 1

  if [ "$prefix" = "/" ]; then
    [ "$target" = "/" ]
    return $?
  fi

  prefix="${prefix%/}"
  target="${target%/}"

  [ "$target" = "$prefix" ] && return 0
  case "$target" in
    "$prefix"/*) return 0 ;;
    *) return 1 ;;
  esac
}

sfb_read_config_value() {
  local key="$1"
  sfb_select_state_paths
  [ -f "$SFB_CONFIG_FILE" ] || return 0
  awk -F= -v k="$key" '$1==k{val=substr($0, index($0,$2))} END{if (val!="") print val}' "$SFB_CONFIG_FILE"
}

sfb_config_set_value() {
  local key="$1"
  local value="$2"
  local dir tmp

  sfb_select_state_paths
  dir="$(dirname "$SFB_CONFIG_FILE")"
  touch "$SFB_CONFIG_FILE"

  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" '
    BEGIN { done=0 }
    $0 ~ "^" k "=" {
      print k "=" v
      done=1
      next
    }
    { print }
    END {
      if (!done) print k "=" v
    }
  ' "$SFB_CONFIG_FILE" > "$tmp"

  mv "$tmp" "$SFB_CONFIG_FILE"
  sfb_invalidate_classification_context
}

sfb_list_contains_path() {
  local needle="$1"
  shift
  local p
  for p in "$@"; do
    [ "$p" = "$needle" ] && return 0
  done
  return 1
}

sfb_csv_to_paths() {
  local csv="$1"
  local out=()
  [ -z "$csv" ] && {
    printf '\n'
    return 0
  }
  local oldifs="$IFS"
  IFS=':'
  local parts=()
  read -r -a parts <<< "$csv"
  IFS="$oldifs"
  local part
  for part in "${parts[@]}"; do
    [ -z "$part" ] && continue
    out+=("$(sfb_abspath "$part" 2>/dev/null || printf '%s' "$part")")
  done
  printf '%s\n' "${out[@]}"
}

sfb_paths_to_csv() {
  local out_csv=""
  local p
  for p in "$@"; do
    [ -z "$p" ] && continue
    if [ -z "$out_csv" ]; then
      out_csv="$p"
    else
      out_csv="$out_csv:$p"
    fi
  done
  printf '%s' "$out_csv"
}

sfb_load_config() {
  local v
  v="$(sfb_read_config_value "SFB_ALLOW_HIGH_RISK_DELETE")"
  [ -n "$v" ] && SFB_ALLOW_HIGH_RISK_DELETE="$v"

  v="$(sfb_read_config_value "SFB_TOKEN_TTL_SECONDS")"
  [ -n "$v" ] && SFB_TOKEN_TTL_SECONDS="$v"

  v="$(sfb_read_config_value "SFB_EXTRA_PROTECTED_PATHS")"
  [ -n "$v" ] && SFB_EXTRA_PROTECTED_PATHS="$v"

  v="$(sfb_read_config_value "SFB_UNPROTECTED_PATHS")"
  [ -n "$v" ] && SFB_UNPROTECTED_PATHS="$v"
}

sfb_collect_protected_arrays() {
  SFB_EXTRA_PROTECTED=()
  SFB_UNPROTECTED=()

  local line csv
  csv="$(sfb_csv_to_paths "$SFB_EXTRA_PROTECTED_PATHS")"
  while IFS= read -r line; do
    [ -n "$line" ] && SFB_EXTRA_PROTECTED+=("$line")
  done <<< "$csv"

  csv="$(sfb_csv_to_paths "$SFB_UNPROTECTED_PATHS")"
  while IFS= read -r line; do
    [ -n "$line" ] && SFB_UNPROTECTED+=("$line")
  done <<< "$csv"
}

sfb_invalidate_classification_context() {
  SFB_CLASSIFICATION_READY=0
}

sfb_prepare_classification_context() {
  sfb_load_config
  sfb_collect_protected_arrays
  SFB_CLASSIFICATION_READY=1
}

sfb_is_unprotected() {
  local path="$1"
  local p
  for p in "${SFB_UNPROTECTED[@]-}"; do
    [ -z "$p" ] && continue
    sfb_path_is_under "$path" "$p" && return 0
  done
  return 1
}

# shellcheck disable=SC2034
sfb_classify_path() {
  local original="$1"
  local path
  path="$(sfb_abspath "$original" 2>/dev/null || printf '%s' "$original")"

  SFB_PATH_CANONICAL="$path"
  SFB_PATH_TIER="low"
  SFB_PATH_PROTECTED=false
  SFB_PATH_BLOCKED=0
  SFB_PATH_REASON="normal"

  if [ "${SFB_CLASSIFICATION_READY:-0}" -ne 1 ]; then
    sfb_prepare_classification_context
  fi

  local p
  for p in "${SFB_HARD_PROTECTED[@]}"; do
    sfb_path_is_under "$path" "$p" || continue
    SFB_PATH_TIER="high"
    SFB_PATH_PROTECTED=true
    SFB_PATH_BLOCKED=1
    SFB_PATH_REASON="hard-protected system path"
    return 0
  done

  if sfb_is_unprotected "$path"; then
    SFB_PATH_TIER="low"
    SFB_PATH_PROTECTED=false
    SFB_PATH_BLOCKED=0
    SFB_PATH_REASON="explicitly unprotected"
    return 0
  fi

  for p in "${SFB_HOME_CRITICAL[@]}"; do
    sfb_path_is_under "$path" "$p" || continue
    SFB_PATH_TIER="high"
    SFB_PATH_PROTECTED=true
    if [ "$SFB_ALLOW_HIGH_RISK_DELETE" = "1" ]; then
      SFB_PATH_BLOCKED=0
      SFB_PATH_REASON="high-risk path requires explicit confirmation"
    else
      SFB_PATH_BLOCKED=1
      SFB_PATH_REASON="protected home-critical path"
    fi
    return 0
  done

  for p in "${SFB_EXTRA_PROTECTED[@]-}"; do
    [ -z "$p" ] && continue
    sfb_path_is_under "$path" "$p" || continue
    SFB_PATH_TIER="high"
    SFB_PATH_PROTECTED=true
    if [ "$SFB_ALLOW_HIGH_RISK_DELETE" = "1" ]; then
      SFB_PATH_BLOCKED=0
      SFB_PATH_REASON="high-risk path requires explicit confirmation"
    else
      SFB_PATH_BLOCKED=1
      SFB_PATH_REASON="custom protected path"
    fi
    return 0
  done

  case "$path" in
    "$HOME"/.*)
      SFB_PATH_TIER="medium"
      SFB_PATH_PROTECTED=false
      SFB_PATH_BLOCKED=0
      SFB_PATH_REASON="hidden path"
      ;;
  esac
}

sfb_protect_list() {
  sfb_prepare_classification_context

  printf 'Hard protected (immutable):\n'
  printf '  %s\n' "${SFB_HARD_PROTECTED[@]}"

  printf 'Home critical (high risk):\n'
  printf '  %s\n' "${SFB_HOME_CRITICAL[@]}"

  printf 'Custom protected:\n'
  if [ -z "${SFB_EXTRA_PROTECTED_PATHS:-}" ]; then
    printf '  (none)\n'
  else
    printf '  %s\n' "${SFB_EXTRA_PROTECTED[@]-}"
  fi

  printf 'Explicitly unprotected overrides:\n'
  if [ -z "${SFB_UNPROTECTED_PATHS:-}" ]; then
    printf '  (none)\n'
  else
    printf '  %s\n' "${SFB_UNPROTECTED[@]-}"
  fi
}

sfb_protect_add() {
  local path
  path="$(sfb_abspath "$1")" || {
    printf 'Could not resolve path: %s\n' "$1" >&2
    return 1
  }

  sfb_prepare_classification_context

  if sfb_list_contains_path "$path" "${SFB_EXTRA_PROTECTED[@]-}"; then
    printf 'Path already in custom protected list: %s\n' "$path"
    return 0
  fi

  SFB_EXTRA_PROTECTED+=("$path")
  sfb_config_set_value "SFB_EXTRA_PROTECTED_PATHS" "$(sfb_paths_to_csv "${SFB_EXTRA_PROTECTED[@]-}")"
  printf 'Added custom protected path: %s\n' "$path"
}

sfb_protect_remove() {
  local path
  path="$(sfb_abspath "$1")" || {
    printf 'Could not resolve path: %s\n' "$1" >&2
    return 1
  }

  sfb_prepare_classification_context

  local p
  for p in "${SFB_HARD_PROTECTED[@]}"; do
    if [ "$p" = "$path" ]; then
      printf 'Cannot unprotect immutable path: %s\n' "$path" >&2
      return 3
    fi
  done

  local updated=()
  local removed=0
  for p in "${SFB_EXTRA_PROTECTED[@]-}"; do
    if [ "$p" = "$path" ]; then
      removed=1
      continue
    fi
    updated+=("$p")
  done

  if [ "$removed" -eq 1 ]; then
    sfb_config_set_value "SFB_EXTRA_PROTECTED_PATHS" "$(sfb_paths_to_csv "${updated[@]-}")"
    printf 'Removed from custom protected list: %s\n' "$path"
    return 0
  fi

  if ! sfb_list_contains_path "$path" "${SFB_UNPROTECTED[@]-}"; then
    SFB_UNPROTECTED+=("$path")
    sfb_config_set_value "SFB_UNPROTECTED_PATHS" "$(sfb_paths_to_csv "${SFB_UNPROTECTED[@]-}")"
    printf 'Added unprotected override: %s\n' "$path"
  else
    printf 'Path already explicitly unprotected: %s\n' "$path"
  fi
}

sfb_issue_unlock_token() {
  sfb_load_config
  local now expiry token user host dir
  now="$(date +%s)"
  expiry=$((now + SFB_TOKEN_TTL_SECONDS))
  token="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  user="$(id -un)"
  host="$(hostname -s 2>/dev/null || hostname)"

  sfb_select_state_paths
  dir="$(dirname "$SFB_TOKEN_FILE")"
  umask 077
  cat > "$SFB_TOKEN_FILE" <<TOKEN
TOKEN=$token
EXPIRY=$expiry
USER=$user
HOST=$host
TOKEN

  printf '%s\n' "$token"
}

# shellcheck disable=SC2034
sfb_validate_unlock_token() {
  local token="$1"
  SFB_TOKEN_VALIDATION_ERROR=""
  sfb_select_state_paths

  [ -f "$SFB_TOKEN_FILE" ] || {
    SFB_TOKEN_VALIDATION_ERROR="no token session found; run sfb unlock"
    return 1
  }

  local file_token file_expiry file_user file_host now
  file_token="$(awk -F= '$1=="TOKEN"{print $2}' "$SFB_TOKEN_FILE")"
  file_expiry="$(awk -F= '$1=="EXPIRY"{print $2}' "$SFB_TOKEN_FILE")"
  file_user="$(awk -F= '$1=="USER"{print $2}' "$SFB_TOKEN_FILE")"
  file_host="$(awk -F= '$1=="HOST"{print $2}' "$SFB_TOKEN_FILE")"

  [ -n "$file_token" ] || {
    SFB_TOKEN_VALIDATION_ERROR="invalid token session file"
    return 1
  }

  [ "$token" = "$file_token" ] || {
    SFB_TOKEN_VALIDATION_ERROR="unlock token mismatch"
    return 1
  }

  now="$(date +%s)"
  if [ "$now" -gt "$file_expiry" ]; then
    SFB_TOKEN_VALIDATION_ERROR="unlock token expired"
    return 1
  fi

  if [ "$(id -un)" != "$file_user" ]; then
    SFB_TOKEN_VALIDATION_ERROR="unlock token user mismatch"
    return 1
  fi

  local host
  host="$(hostname -s 2>/dev/null || hostname)"
  if [ "$host" != "$file_host" ]; then
    SFB_TOKEN_VALIDATION_ERROR="unlock token host mismatch"
    return 1
  fi

  return 0
}

sfb_confirm_yes_no() {
  local prompt="$1"
  printf '%s [y/N]: ' "$prompt"
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

sfb_confirm_typed_phrase() {
  local phrase="$1"
  printf 'Type "%s" to continue: ' "$phrase"
  local answer
  read -r answer
  [ "$answer" = "$phrase" ]
}
