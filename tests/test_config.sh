#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/setup.sh"

CONFIG_GET_PROVIDER="$($AI_BIN --config "$CONFIG_FILE" config get provider)"
[[ "$CONFIG_GET_PROVIDER" == "codex" ]] || fail "Expected config get provider=codex, got: $CONFIG_GET_PROVIDER"

CONFIG_SET_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" config set profiles.gemini.model gemini-2.0-flash)"
[[ "$CONFIG_SET_OUTPUT" == *"Set profiles.gemini.model in $CONFIG_FILE"* ]] || fail "Expected config set confirmation output."

CONFIG_GET_PROFILE_MODEL="$($AI_BIN --config "$CONFIG_FILE" config get profiles.gemini.model)"
[[ "$CONFIG_GET_PROFILE_MODEL" == "gemini-2.0-flash" ]] || fail "Expected profile model after set, got: $CONFIG_GET_PROFILE_MODEL"

CONFIG_SET_UI_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" config set ui pretty)"
[[ "$CONFIG_SET_UI_OUTPUT" == *"Set ui in $CONFIG_FILE"* ]] || fail "Expected config set ui confirmation output."
CONFIG_GET_UI="$($AI_BIN --config "$CONFIG_FILE" config get ui)"
[[ "$CONFIG_GET_UI" == "pretty" ]] || fail "Expected ui=pretty after set, got: $CONFIG_GET_UI"

CONFIG_SET_META_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" config set show_meta true)"
[[ "$CONFIG_SET_META_OUTPUT" == *"Set show_meta in $CONFIG_FILE"* ]] || fail "Expected config set show_meta confirmation output."
CONFIG_GET_META="$($AI_BIN --config "$CONFIG_FILE" config get show_meta)"
[[ "$CONFIG_GET_META" == "1" ]] || fail "Expected normalized show_meta=1 after set, got: $CONFIG_GET_META"

CONFIG_SET_EMPTY_ROOT_MODEL_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" config set model "")"
[[ "$CONFIG_SET_EMPTY_ROOT_MODEL_OUTPUT" == *"Set model in $CONFIG_FILE"* ]] || fail "Expected config set model confirmation output for empty value."
CONFIG_GET_EMPTY_ROOT_MODEL="$($AI_BIN --config "$CONFIG_FILE" config get model)"
[[ "$CONFIG_GET_EMPTY_ROOT_MODEL" == "" ]] || fail "Expected empty root model value, got: $CONFIG_GET_EMPTY_ROOT_MODEL"

CONFIG_SET_EMPTY_PROFILE_MODEL_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" config set profiles.gemini.model "")"
[[ "$CONFIG_SET_EMPTY_PROFILE_MODEL_OUTPUT" == *"Set profiles.gemini.model in $CONFIG_FILE"* ]] || fail "Expected config set profiles.gemini.model confirmation output for empty value."
CONFIG_GET_EMPTY_PROFILE_MODEL="$($AI_BIN --config "$CONFIG_FILE" config get profiles.gemini.model)"
[[ "$CONFIG_GET_EMPTY_PROFILE_MODEL" == "" ]] || fail "Expected empty profile model value, got: $CONFIG_GET_EMPTY_PROFILE_MODEL"

if $AI_BIN --config "$CONFIG_FILE" config get profiles.invalid >/dev/null 2>"$TMP_DIR/config_get.err"; then
  fail "Expected invalid config get path to fail."
fi
grep -q "Unsupported config path" "$TMP_DIR/config_get.err" || fail "Expected invalid config path error."

echo "tests/test_config.sh: OK"
