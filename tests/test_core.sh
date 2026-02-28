#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/setup.sh"

HOME="$TMP_DIR" OUTPUT_PRINT="$($AI_BIN --config "$CONFIG_FILE" "anything")"
[[ "$OUTPUT_PRINT" == "printf run-ok" ]] || fail "Expected printed command 'printf run-ok', got: $OUTPUT_PRINT"

HOME="$TMP_DIR" OUTPUT_QUIET="$($AI_BIN --config "$CONFIG_FILE" --quiet "anything")"
[[ "$OUTPUT_QUIET" == "printf run-ok" ]] || fail "Expected quiet output 'printf run-ok', got: $OUTPUT_QUIET"

HOME="$TMP_DIR" OUTPUT_PRETTY="$($AI_BIN --config "$CONFIG_FILE" --ui pretty "anything")"
[[ "$OUTPUT_PRETTY" == *"Suggested command"* && "$OUTPUT_PRETTY" == *"printf run-ok"* ]] || fail "Expected pretty output block with suggested command."

HOME="$TMP_DIR" OUTPUT_PRETTY_META="$($AI_BIN --config "$CONFIG_FILE" --ui pretty --meta "anything")"
[[ "$OUTPUT_PRETTY_META" == *"provider: codex"* && "$OUTPUT_PRETTY_META" == *"mode: strict"* ]] || fail "Expected pretty output metadata line."

HELP_PROFILE_OUTPUT="$($AI_BIN help profile)"
[[ "$HELP_PROFILE_OUTPUT" == *"Topic: profile"* ]] || fail "Expected help profile topic output."

OUTPUT_AUTO_COPY="$(HOME="$TMP_DIR" AI_CLI_OS=Darwin PATH="$TMP_DIR:$PATH" PBCOPY_CAPTURE="$PBCOPY_CAPTURE" $AI_BIN --config "$CONFIG_FILE" "anything")"
[[ "$OUTPUT_AUTO_COPY" == "printf run-ok" ]] || fail "Expected auto-copy command output 'printf run-ok', got: $OUTPUT_AUTO_COPY"
[[ "$(cat "$PBCOPY_CAPTURE")" == "printf run-ok" ]] || fail "Expected auto-copy clipboard content 'printf run-ok'."

VERSION_FLAG_OUTPUT="$($AI_BIN --version)"
[[ "$VERSION_FLAG_OUTPUT" == "ai v0.0.1" ]] || fail "Expected --version output 'ai v0.0.1', got: $VERSION_FLAG_OUTPUT"

LINK_BIN_DIR="$TMP_DIR/link-bin"
mkdir -p "$LINK_BIN_DIR"
ln -s "$AI_BIN" "$LINK_BIN_DIR/ai"
LINK_VERSION_OUTPUT="$($LINK_BIN_DIR/ai --version)"
[[ "$LINK_VERSION_OUTPUT" == "ai v0.0.1" ]] || fail "Expected symlinked ai --version output 'ai v0.0.1', got: $LINK_VERSION_OUTPUT"

HOME="$TMP_DIR" OUTPUT_DRY_RUN="$($AI_BIN --config "$CONFIG_FILE" --dry-run "anything")"
[[ "$OUTPUT_DRY_RUN" == "printf run-ok" ]] || fail "Expected dry-run output 'printf run-ok', got: $OUTPUT_DRY_RUN"

HOME="$TMP_DIR" OUTPUT_RUN="$($AI_BIN --config "$CONFIG_FILE" --run "anything")"
[[ "$OUTPUT_RUN" == "run-ok" ]] || fail "Expected executed output 'run-ok', got: $OUTPUT_RUN"

HOME="$TMP_DIR" OUTPUT_EXPLAIN="$($AI_BIN --config "$CONFIG_FILE" --explain "anything")"
EXPECTED_EXPLAIN=$'printf run-ok\nExplanation: Prints run-ok in the current shell.'
[[ "$OUTPUT_EXPLAIN" == "$EXPECTED_EXPLAIN" ]] || fail "Unexpected explain output: $OUTPUT_EXPLAIN"

HOME="$TMP_DIR" OUTPUT_SHELL="$($AI_BIN --config "$CONFIG_FILE" --shell fish "anything")"
[[ "$OUTPUT_SHELL" == "echo fish-shell" ]] || fail "Expected shell-specific command 'echo fish-shell', got: $OUTPUT_SHELL"

HOME="$TMP_DIR" OUTPUT_PROFILE="$($AI_BIN --config "$CONFIG_FILE" --profile fast "profile-case")"
[[ "$OUTPUT_PROFILE" == "echo profile-fast" ]] || fail "Expected profile command 'echo profile-fast', got: $OUTPUT_PROFILE"

HOME="$TMP_DIR" OUTPUT_PROMPT_MODE_FLAG="$($AI_BIN --config "$CONFIG_FILE" --prompt-mode creative "anything")"
[[ "$OUTPUT_PROMPT_MODE_FLAG" == "echo creative-mode" ]] || fail "Expected creative prompt mode command 'echo creative-mode', got: $OUTPUT_PROMPT_MODE_FLAG"

HOME="$TMP_DIR" OUTPUT_PROMPT_MODE_PROFILE="$($AI_BIN --config "$CONFIG_FILE" --profile fast "anything")"
[[ "$OUTPUT_PROMPT_MODE_PROFILE" == "echo creative-mode" ]] || fail "Expected profile prompt_mode command 'echo creative-mode', got: $OUTPUT_PROMPT_MODE_PROFILE"

HOME="$TMP_DIR" OUTPUT_RETRY="$($AI_BIN --config "$CONFIG_FILE" --max-retries 2 "retry-case")"
[[ "$OUTPUT_RETRY" == "echo recovered" ]] || fail "Expected retried command 'echo recovered', got: $OUTPUT_RETRY"

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" --timeout 1 "slow-case" >/dev/null 2>"$TMP_DIR/timeout.err"; then
  fail "Expected timeout failure."
fi
grep -q "Timed out after 1s" "$TMP_DIR/timeout.err" || fail "Expected timeout message."

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" "model-unsupported-case" >/dev/null 2>"$TMP_DIR/model.err"; then
  fail "Expected model unsupported failure."
fi
grep -q "model is not supported when using Codex with a ChatGPT account" "$TMP_DIR/model.err" || fail "Expected concise model unsupported message."
if grep -q "OpenAI Codex v0.101.0" "$TMP_DIR/model.err"; then
  fail "Expected verbose provider output to be filtered out."
fi

HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" PBCOPY_CAPTURE="$PBCOPY_CAPTURE" $AI_BIN --config "$CONFIG_FILE" --copy "anything" >/dev/null
[[ "$(cat "$PBCOPY_CAPTURE")" == "printf run-ok" ]] || fail "Expected clipboard content 'printf run-ok'."

mv "$FAKE_PBCOPY" "$TMP_DIR/pbcopy-ok"
cp "$FAILING_PBCOPY" "$TMP_DIR/pbcopy"
HOME="$TMP_DIR" AI_CLI_OS=Linux PATH="$TMP_DIR:$PATH" XCLIP_CAPTURE="$XCLIP_CAPTURE" $AI_BIN --config "$CONFIG_FILE" --copy "anything" >/dev/null
[[ "$(cat "$XCLIP_CAPTURE")" == "printf run-ok" ]] || fail "Expected Linux clipboard content via xclip."

HOME="$TMP_DIR" OUTPUT_JSON="$($AI_BIN --config "$CONFIG_FILE" --json --explain "anything")"
[[ "$OUTPUT_JSON" == *'"command":"printf run-ok"'* ]] || fail "Expected JSON output with command."
[[ "$OUTPUT_JSON" == *'"prompt_mode":"strict"'* ]] || fail "Expected JSON output with prompt_mode."
[[ "$OUTPUT_JSON" == *'"explanation":"Prints run-ok in the current shell."'* ]] || fail "Expected JSON output with explanation."

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" --run --dry-run "anything" >/dev/null 2>"$TMP_DIR/invalid.err"; then
  fail "Expected --run --dry-run conflict error."
fi
grep -q "cannot be used together" "$TMP_DIR/invalid.err" || fail "Expected conflict error text."

echo "tests/test_core.sh: OK"
