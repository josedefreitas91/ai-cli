#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/setup.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/setup.sh"

PROVIDERS_LIST="$($AI_BIN providers list)"
[[ "$PROVIDERS_LIST" == *"Providers"* && "$PROVIDERS_LIST" == *"codex"* && "$PROVIDERS_LIST" == *"opencode"* ]] || fail "Expected providers list output."

PROVIDERS_CHECK="$($AI_BIN providers check)"
[[ "$PROVIDERS_CHECK" == *"Provider checks"* && "$PROVIDERS_CHECK" == *"auth="* ]] || fail "Expected providers check output."

if HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" --run "dangerous" >/dev/null 2>"$TMP_DIR/danger.err"; then
  fail "Expected dangerous command to require confirmation."
fi
grep -q "requires confirmation" "$TMP_DIR/danger.err" || fail "Expected confirmation requirement message for dangerous command."

HOME="$TMP_DIR" OUTPUT_CONFIRM_RUN="$(printf 'y\n' | $AI_BIN --config "$CONFIG_FILE" --run --confirm "anything")"
[[ "$OUTPUT_CONFIRM_RUN" == "run-ok" ]] || fail "Expected confirmed run output run-ok, got: $OUTPUT_CONFIRM_RUN"

HOME="$TMP_DIR" DOCTOR_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" doctor)"
[[ "$DOCTOR_OUTPUT" == *"ai doctor"* ]] || fail "Expected doctor output."

HOME="$TMP_DIR" DOCTOR_EMPTY_MODEL_OUTPUT="$($AI_BIN --config "$CONFIG_FILE" --model "" doctor)"
[[ "$DOCTOR_EMPTY_MODEL_OUTPUT" == *"Effective model: <empty>"* ]] || fail "Expected doctor to report empty effective model with --model \"\"."

INIT_CONFIG="$TMP_DIR/init-config.toml"
INIT_OUTPUT="$($AI_BIN --config "$INIT_CONFIG" init)"
[[ "$INIT_OUTPUT" == *"Created config at $INIT_CONFIG"* ]] || fail "Expected init output with created config path."
[[ -f "$INIT_CONFIG" ]] || fail "Expected init to create config file."
grep -q '^\[profiles.gemini\]$' "$INIT_CONFIG" || fail "Expected init config to include gemini profile."
grep -q '^\[profiles.opencode\]$' "$INIT_CONFIG" || fail "Expected init config to include opencode profile."

if $AI_BIN --config "$INIT_CONFIG" init >/dev/null 2>"$TMP_DIR/init.err"; then
  fail "Expected init without --force to fail when config exists."
fi
grep -q "Use 'ai init --force' to overwrite" "$TMP_DIR/init.err" || fail "Expected init overwrite guidance."

FORCED_INIT_OUTPUT="$($AI_BIN --config "$INIT_CONFIG" --force init)"
[[ "$FORCED_INIT_OUTPUT" == *"Created config at $INIT_CONFIG"* ]] || fail "Expected forced init output with created config path."

ZSH_COMPLETION="$($AI_BIN completion zsh)"
[[ "$ZSH_COMPLETION" == *"#compdef ai"* ]] || fail "Expected zsh completion content."

BASH_COMPLETION="$($AI_BIN completion bash)"
[[ "$BASH_COMPLETION" == *"_ai_completions"* ]] || fail "Expected bash completion content."

FISH_COMPLETION="$($AI_BIN completion fish)"
[[ "$FISH_COMPLETION" == *"complete -c ai -f"* ]] || fail "Expected fish completion content."

if $AI_BIN completion powershell >/dev/null 2>"$TMP_DIR/completion.err"; then
  fail "Expected unsupported completion shell to fail."
fi
grep -q "Unsupported completion shell" "$TMP_DIR/completion.err" || fail "Expected unsupported completion shell error message."

FAKE_CURL="$TMP_DIR/curl"
cat > "$FAKE_CURL" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
cat <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${UPDATE_CAPTURE:?UPDATE_CAPTURE missing}"
SCRIPT
CURL
chmod +x "$FAKE_CURL"

UPDATE_CAPTURE="$TMP_DIR/update-capture.txt"
HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" UPDATE_CAPTURE="$UPDATE_CAPTURE" $AI_BIN update >/dev/null
grep -q '^--repo$' "$UPDATE_CAPTURE" || fail "Expected ai update to pass --repo flag."
grep -q '^josedefreitas91/ai-cli$' "$UPDATE_CAPTURE" || fail "Expected ai update default repo value."

HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" UPDATE_CAPTURE="$UPDATE_CAPTURE" \
  $AI_BIN update --ref tags/v0.0.1 --scope global >/dev/null
grep -q '^--ref$' "$UPDATE_CAPTURE" || fail "Expected ai update to pass --ref flag."
grep -q '^tags/v0.0.1$' "$UPDATE_CAPTURE" || fail "Expected ai update ref value."
grep -q '^--scope$' "$UPDATE_CAPTURE" || fail "Expected ai update to pass --scope flag."
grep -q '^global$' "$UPDATE_CAPTURE" || fail "Expected ai update scope value."

if HOME="$TMP_DIR" PATH="$TMP_DIR:$PATH" $AI_BIN --ref tags/v0.0.1 "anything" >/dev/null 2>"$TMP_DIR/update_ref.err"; then
  fail "Expected --ref without update to fail."
fi
grep -q "can only be used with 'ai update'" "$TMP_DIR/update_ref.err" || fail "Expected --ref validation message."

UNINSTALL_HELP="$($AI_BIN help uninstall)"
[[ "$UNINSTALL_HELP" == *"Topic: uninstall"* ]] || fail "Expected help uninstall topic output."
UPDATE_HELP="$($AI_BIN help update)"
[[ "$UPDATE_HELP" == *"Topic: update"* ]] || fail "Expected help update topic output."

if $AI_BIN uninstall extra >/dev/null 2>"$TMP_DIR/uninstall.err"; then
  fail "Expected uninstall extra args to fail."
fi
grep -q "uninstall does not accept additional positional arguments" "$TMP_DIR/uninstall.err" || fail "Expected uninstall positional argument validation."

UNINSTALL_BIN_DIR="$TMP_DIR/uninstall-bin"
UNINSTALL_APP_HOME="$TMP_DIR/uninstall-app-home"
mkdir -p "$UNINSTALL_BIN_DIR" "$UNINSTALL_APP_HOME/lib" "$TMP_DIR/.config/ai-cli/history"
printf '#!/usr/bin/env bash\n' > "$UNINSTALL_BIN_DIR/ai"
touch "$UNINSTALL_APP_HOME/lib/config.sh" "$TMP_DIR/.config/ai-cli/config.toml"
HOME="$TMP_DIR" UNINSTALL_OUTPUT="$(printf '%s\n%s\ny\nn\nn\ny\n' "$UNINSTALL_BIN_DIR" "$UNINSTALL_APP_HOME" | $AI_BIN uninstall)"
[[ "$UNINSTALL_OUTPUT" == *"Uninstall completed."* ]] || fail "Expected uninstall completion output."
[[ ! -e "$UNINSTALL_BIN_DIR/ai" ]] || fail "Expected uninstall to remove launcher."
[[ ! -d "$UNINSTALL_APP_HOME" ]] || fail "Expected uninstall to remove app home."

printf 'custom\ncodex\ncustom-model\nCOUNTER_FILE=%s %s {PROMPT}\nbash\n40\n3\nstrict\ncompact\n0\n' "$COUNTER_FILE" "$FAKE_PROVIDER" | \
  HOME="$TMP_DIR" $AI_BIN --config "$CONFIG_FILE" profile >/dev/null

grep -q '^\[profiles.custom\]$' "$CONFIG_FILE" || fail "Expected custom profile section in config file."

HOME="$TMP_DIR" OUTPUT_CUSTOM_PROFILE="$($AI_BIN --config "$CONFIG_FILE" --profile custom "anything")"
[[ "$OUTPUT_CUSTOM_PROFILE" == "printf run-ok" ]] || fail "Expected custom profile output 'printf run-ok', got: $OUTPUT_CUSTOM_PROFILE"

echo "tests/test_commands.sh: OK"
