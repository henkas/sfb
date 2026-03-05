#!/usr/bin/env bats

setup() {
  TEST_ROOT="$BATS_TEST_DIRNAME/.tmp-$BATS_TEST_NUMBER-$$-$RANDOM"
  mkdir -p "$TEST_ROOT"
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"

  export SFB_CONFIG_FILE="$TEST_ROOT/config"
  export SFB_TOKEN_FILE="$TEST_ROOT/token"
  export SFB_TEST_TRASH_LOG="$TEST_ROOT/trashed.log"

  mkdir -p "$TEST_ROOT/bin"

  cat > "$TEST_ROOT/bin/trash" <<'TRASH'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" = "--" ] && continue
  printf '%s\n' "$arg" >> "${SFB_TEST_TRASH_LOG}"
done
TRASH

  cat > "$TEST_ROOT/bin/fzf" <<'FZF'
#!/usr/bin/env bash
head -n 1
FZF

  chmod +x "$TEST_ROOT/bin/trash" "$TEST_ROOT/bin/fzf"
  export PATH="$TEST_ROOT/bin:$PATH"

  mkdir -p "$TEST_ROOT/work/a"
  printf 'hello\n' > "$TEST_ROOT/work/a/file1.txt"
  printf 'world\n' > "$TEST_ROOT/work/file2.txt"
  printf 'hidden\n' > "$TEST_ROOT/work/.secret.txt"

  mkdir -p "$HOME/.ssh"
  printf 'key\n' > "$HOME/.ssh/id_rsa"

  SFB_BIN="$BATS_TEST_DIRNAME/../bin/sfb"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "help command works" {
  run "$SFB_BIN" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Smart File Browser"* ]]
}

@test "list command emits json" {
  run "$SFB_BIN" list "$TEST_ROOT/work" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"entries"'* ]]
  [[ "$output" == *'"path"'* ]]
}

@test "scan --human prints readable table sizes" {
  run "$SFB_BIN" scan "$TEST_ROOT/work" --top 5 --human
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIZE"* ]]
  [[ "$output" == *"KB"* || "$output" == *"B"* ]]
}

@test "repeated scans do not fail with descriptor-style errors" {
  local i
  for i in $(seq 1 15); do
    run "$SFB_BIN" scan "$TEST_ROOT/work" --top 20
    [ "$status" -eq 0 ]
    [[ "$output" != *"Too many open files"* ]]
  done
}

@test "trash command requires authorization flags" {
  run "$SFB_BIN" trash "$TEST_ROOT/work/file2.txt"
  [ "$status" -eq 5 ]
  [[ "$output" == *"Delete authorization failed"* ]]
}

@test "trash command blocks when token is missing" {
  run "$SFB_BIN" trash "$TEST_ROOT/work/file2.txt" --allow-delete
  [ "$status" -eq 5 ]
  [[ "$output" == *"missing --unlock-token"* ]]
}

@test "trash command moves file when unlocked" {
  token="$($SFB_BIN unlock)"
  run "$SFB_BIN" trash "$TEST_ROOT/work/file2.txt" --allow-delete --unlock-token "$token"
  [ "$status" -eq 0 ]
  grep -q "$TEST_ROOT/work/file2.txt" "$SFB_TEST_TRASH_LOG"
}

@test "home critical path is blocked" {
  token="$($SFB_BIN unlock)"
  run "$SFB_BIN" trash "$HOME/.ssh/id_rsa" --allow-delete --unlock-token "$token"
  [ "$status" -eq 3 ]
  [[ "$output" == *"protected home-critical path"* ]]
}

@test "hard protected path is blocked" {
  token="$($SFB_BIN unlock)"
  run "$SFB_BIN" trash "/" --allow-delete --unlock-token "$token"
  [ "$status" -eq 3 ]
  [[ "$output" == *"hard-protected system path"* ]]
}

@test "protect add and list" {
  run "$SFB_BIN" protect add "$TEST_ROOT/work/a"
  [ "$status" -eq 0 ]

  run "$SFB_BIN" protect list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_ROOT/work/a"* ]]
}

@test "summary command emits json report" {
  run "$SFB_BIN" summary "$TEST_ROOT/work" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"summary"'* ]]
  [[ "$output" == *'"total_bytes"'* ]]
  [[ "$output" == *'"file_count"'* ]]
  [[ "$output" == *'"top_by_size"'* ]]
  [[ "$output" == *'"extensions"'* ]]
}

@test "find command emits json and respects name pattern" {
  run "$SFB_BIN" find "$TEST_ROOT/work" --name '*.txt' --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"entries"'* ]]
  [[ "$output" == *'"file1.txt"'* ]]
  [[ "$output" == *'"file2.txt"'* ]]
}

@test "find command includes directories with zero bytes" {
  run "$SFB_BIN" find "$TEST_ROOT/work" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"a","bytes":0,"kind":"dir"'* ]]
}
