#!/usr/bin/env bash

SFB_REQUIRED_CMDS=(du find sort awk sed fzf trash)
sfb_join_by_comma() {
  local IFS=','
  printf '%s' "$*"
}

sfb_collect_dependencies() {
  if [ -n "${SFB_REQUIRED_CMDS_CSV:-}" ]; then
    local oldifs="$IFS"
    IFS=','
    # shellcheck disable=SC2206
    SFB_REQUIRED_CMDS=(${SFB_REQUIRED_CMDS_CSV})
    IFS="$oldifs"
  fi

  SFB_MISSING_CMDS=()
  SFB_INSTALLED_CMDS=()
  local cmd
  for cmd in "${SFB_REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      SFB_INSTALLED_CMDS+=("$cmd")
    else
      SFB_MISSING_CMDS+=("$cmd")
    fi
  done
}

sfb_require_dependencies() {
  sfb_collect_dependencies
  if [ "${#SFB_MISSING_CMDS[@]}" -gt 0 ]; then
    printf 'Missing required dependencies: %s\n' "$(sfb_join_by_comma "${SFB_MISSING_CMDS[@]}")" >&2
    printf 'Run: sfb doctor --install-deps\n' >&2
    return 4
  fi
  return 0
}

sfb_brew_formula_for_cmd() {
  case "$1" in
    fzf) printf 'fzf' ;;
    trash) printf 'trash' ;;
    *) printf '%s' "$1" ;;
  esac
}

sfb_print_install_help() {
  if [ "${#SFB_MISSING_CMDS[@]}" -eq 0 ]; then
    return 0
  fi
  local formulas=()
  local cmd
  for cmd in "${SFB_MISSING_CMDS[@]}"; do
    formulas+=("$(sfb_brew_formula_for_cmd "$cmd")")
  done
  printf 'Install with Homebrew:\n'
  printf '  brew install %s\n' "${formulas[*]}"
}

sfb_install_missing_with_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    printf 'Homebrew is not installed. Visit https://brew.sh\n' >&2
    return 1
  fi

  sfb_collect_dependencies
  if [ "${#SFB_MISSING_CMDS[@]}" -eq 0 ]; then
    printf 'All required dependencies are installed.\n'
    return 0
  fi

  local formulas=()
  local cmd
  for cmd in "${SFB_MISSING_CMDS[@]}"; do
    formulas+=("$(sfb_brew_formula_for_cmd "$cmd")")
  done

  printf 'Missing dependencies: %s\n' "$(sfb_join_by_comma "${SFB_MISSING_CMDS[@]}")"
  printf 'Install now with: brew install %s\n' "${formulas[*]}"
  printf 'Proceed? [y/N]: '
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      brew install "${formulas[@]}"
      ;;
    *)
      printf 'Skipped dependency installation.\n'
      ;;
  esac
}
