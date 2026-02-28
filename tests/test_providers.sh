#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/setup.sh"

OPENCODE_CONFIG="$TMP_DIR/opencode-config.toml"
cat > "$OPENCODE_CONFIG" <<'OCFG'
provider = "opencode"
model = ""
provider_cmd = ""
timeout_seconds = "5"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"
OCFG
HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" OUTPUT_OPENCODE="$($AI_BIN --config "$OPENCODE_CONFIG" "anything")"
[[ "$OUTPUT_OPENCODE" == "echo opencode-ok" ]] || fail "Expected opencode provider output 'echo opencode-ok', got: $OUTPUT_OPENCODE"

HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" OUTPUT_OPENCODE_RAW="$($AI_BIN --config "$OPENCODE_CONFIG" --raw "anything")"
[[ "$OUTPUT_OPENCODE_RAW" == '{"type":"assistant.message.delta","text":"echo opencode-ok"}' ]] || fail "Expected opencode --raw JSON output, got: $OUTPUT_OPENCODE_RAW"

CODEX_RAW_CONFIG="$TMP_DIR/codex-raw-config.toml"
cat > "$CODEX_RAW_CONFIG" <<'CRCFG'
provider = "codex"
model = ""
provider_cmd = ""
timeout_seconds = "5"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"
CRCFG
HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" OUTPUT_CODEX_RAW="$($AI_BIN --config "$CODEX_RAW_CONFIG" --raw "anything")"
[[ "$OUTPUT_CODEX_RAW" == *'{"event":"message.delta","text":"find . -type f -mtime -2 -size +100M -ls"}'* ]] || fail "Expected codex --raw to include JSONL event output."

OPENCODE_MODEL_CONFIG="$TMP_DIR/opencode-model-config.toml"
cat > "$OPENCODE_MODEL_CONFIG" <<'OMCFG'
provider = "opencode"
model = "openai/gpt-4.1"
provider_cmd = ""
timeout_seconds = "5"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"
OMCFG
HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" OUTPUT_OPENCODE_MODEL="$($AI_BIN --config "$OPENCODE_MODEL_CONFIG" "anything")"
[[ "$OUTPUT_OPENCODE_MODEL" == "echo opencode-with-model" ]] || fail "Expected opencode model to pass -m, got: $OUTPUT_OPENCODE_MODEL"

HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" OUTPUT_OPENCODE_EMPTY_MODEL="$($AI_BIN --config "$OPENCODE_MODEL_CONFIG" --model "" "anything")"
[[ "$OUTPUT_OPENCODE_EMPTY_MODEL" == "echo opencode-ok" ]] || fail "Expected --model "" override, got: $OUTPUT_OPENCODE_EMPTY_MODEL"

OPENCODE_PROFILE_CONFIG="$TMP_DIR/opencode-profile-empty-model.toml"
cat > "$OPENCODE_PROFILE_CONFIG" <<'OPCFG'
provider = "opencode"
model = "openai/gpt-4.1"
provider_cmd = ""
timeout_seconds = "5"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"

[profiles.opencode]
provider = "opencode"
model = ""
timeout_seconds = "5"
max_retries = "1"
prompt_mode = "strict"
OPCFG
HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" OUTPUT_OPENCODE_PROFILE_EMPTY_MODEL="$($AI_BIN --config "$OPENCODE_PROFILE_CONFIG" --profile opencode "anything")"
[[ "$OUTPUT_OPENCODE_PROFILE_EMPTY_MODEL" == "echo opencode-ok" ]] || fail "Expected profile model empty override, got: $OUTPUT_OPENCODE_PROFILE_EMPTY_MODEL"

echo "tests/test_providers.sh: OK"
