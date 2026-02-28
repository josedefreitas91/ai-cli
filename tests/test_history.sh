#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/setup.sh"

HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" "anything" >/dev/null
HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" --max-retries 2 "retry-case" >/dev/null

HOME="$TMP_DIR" HISTORY_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" --history)"
[[ "$HISTORY_OUTPUT" == *"printf run-ok"* ]] || fail "Expected history to contain generated command."
[[ "$HISTORY_OUTPUT" == *"id"* ]] || fail "Expected history output to include id column."

HOME="$TMP_DIR" HISTORY_JSON_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" --history --json)"
[[ "$HISTORY_JSON_OUTPUT" == *'"history":['* ]] || fail "Expected --history --json array."
[[ "$HISTORY_JSON_OUTPUT" == *'"id":1'* ]] || fail "Expected --history --json id field."
[[ "$HISTORY_JSON_OUTPUT" == *'"command":"printf run-ok"'* ]] || fail "Expected --history --json command field."

mkdir -p "$TMP_DIR/.config/ai-cli/history"
cat > "$TMP_DIR/.config/ai-cli/history/2000-01-01.log" <<'OLDLOG'
2000-01-01T00:00:00Z	codex		zsh	old-intent	old-command
OLDLOG

HOME="$TMP_DIR" HISTORY_DAYS_ONE="$($AI_BIN --config "$CONFIG_FILE" --history --days 1)"
[[ "$HISTORY_DAYS_ONE" != *"old-command"* ]] || fail "Expected --days 1 to exclude older logs."
[[ "$HISTORY_DAYS_ONE" == *"printf run-ok"* ]] || fail "Expected --days 1 to include latest log."

HOME="$TMP_DIR" HISTORY_SEARCH="$($AI_BIN --config "$CONFIG_FILE" --history --search retry-case)"
[[ "$HISTORY_SEARCH" == *"echo recovered"* ]] || fail "Expected --history --search to include matching command."
[[ "$HISTORY_SEARCH" != *"old-command"* ]] || fail "Expected --history --search to filter rows."

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" --search retry-case >/dev/null 2>"$TMP_DIR/search.err"; then
  fail "Expected --search without --history to fail."
fi
grep -q "can only be used together with --history" "$TMP_DIR/search.err" || fail "Expected --search validation message."

HOME="$TMP_DIR" HISTORY_FULL="$($AI_BIN --config "$CONFIG_FILE" --history --full)"
[[ "$HISTORY_FULL" == *"id | timestamp | provider | model | shell | intent | command"* ]] || fail "Expected --full header."

HOME="$TMP_DIR" REPLAY_LATEST="$($AI_BIN --config "$CONFIG_FILE" replay latest)"
[[ -n "$REPLAY_LATEST" ]] || fail "Expected replay latest command."

HOME="$TMP_DIR" REPLAY_ID_ONE="$($AI_BIN --config "$CONFIG_FILE" replay 1)"
[[ "$REPLAY_ID_ONE" == "old-command" ]] || fail "Expected replay id 1 old-command, got: $REPLAY_ID_ONE"

HOME="$TMP_DIR" REPLAY_RUN_OUTPUT="$(printf 'y\n' | $AI_BIN --config "$CONFIG_FILE" --run replay latest)"
[[ "$REPLAY_RUN_OUTPUT" == "recovered" ]] || fail "Expected replay run output recovered, got: $REPLAY_RUN_OUTPUT"

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" replay unknown >/dev/null 2>"$TMP_DIR/replay.err"; then
  fail "Expected replay unknown to fail."
fi
grep -q "History entry not found" "$TMP_DIR/replay.err" || fail "Expected replay not found message."

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" --full >/dev/null 2>"$TMP_DIR/history_full.err"; then
  fail "Expected --full without --history to fail."
fi
grep -q "can only be used together with --history" "$TMP_DIR/history_full.err" || fail "Expected --full validation message."

echo "tests/test_history.sh: OK"
