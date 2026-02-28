#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI_BIN="$ROOT_DIR/bin/ai"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

FAKE_PROVIDER="$TMP_DIR/fake-provider"
COUNTER_FILE="$TMP_DIR/retry-counter"
cat > "$FAKE_PROVIDER" <<'PROVIDER'
#!/usr/bin/env bash
set -euo pipefail
PROMPT_TEXT="$*"
COUNTER_FILE="${COUNTER_FILE:?COUNTER_FILE missing}"

if [[ "$PROMPT_TEXT" == *"Explain this shell command"* ]]; then
  printf '%s\n' "Prints run-ok in the current shell."
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"profile-case"* ]]; then
  printf '%s\n' "echo profile-fast"
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"Prompt mode: creative"* ]]; then
  printf '%s\n' "echo creative-mode"
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"Target shell: fish"* ]]; then
  printf '%s\n' "echo fish-shell"
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"dangerous"* ]]; then
  printf '%s\n' "rm -rf /tmp/ai-cli-danger"
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"slow-case"* ]]; then
  sleep 3
  printf '%s\n' "echo too-slow"
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"retry-case"* ]]; then
  count=0
  if [[ -f "$COUNTER_FILE" ]]; then
    count="$(cat "$COUNTER_FILE")"
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$COUNTER_FILE"
  if [[ "$count" -lt 2 ]]; then
    echo "transient failure" >&2
    exit 1
  fi
  printf '%s\n' "echo recovered"
  exit 0
fi

if [[ "$PROMPT_TEXT" == *"model-unsupported-case"* ]]; then
  {
    echo "OpenAI Codex v0.101.0 (research preview)"
    echo "workdir: /tmp/project"
    echo "mcp: codex_apps ready"
    echo "ERROR: {\"detail\":\"The 'gpt-5.3-codex-spark' model is not supported when using Codex with a ChatGPT account.\"}"
  } >&2
  exit 1
fi

printf '%s\n' "printf run-ok"
PROVIDER
chmod +x "$FAKE_PROVIDER"

FAKE_PBCOPY="$TMP_DIR/pbcopy"
PBCOPY_CAPTURE="$TMP_DIR/pbcopy_capture.txt"
cat > "$FAKE_PBCOPY" <<'PBCOPY'
#!/usr/bin/env bash
set -euo pipefail
cat > "${PBCOPY_CAPTURE:?PBCOPY_CAPTURE missing}"
PBCOPY
chmod +x "$FAKE_PBCOPY"

FAILING_PBCOPY="$TMP_DIR/pbcopy-fail"
cat > "$FAILING_PBCOPY" <<'PBFAIL'
#!/usr/bin/env bash
set -euo pipefail
exit 1
PBFAIL
chmod +x "$FAILING_PBCOPY"

FAKE_XCLIP="$TMP_DIR/xclip"
XCLIP_CAPTURE="$TMP_DIR/xclip_capture.txt"
cat > "$FAKE_XCLIP" <<'XCLIP'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "-selection" || "${2:-}" != "clipboard" ]]; then
  echo "unexpected xclip args: $*" >&2
  exit 2
fi
cat > "${XCLIP_CAPTURE:?XCLIP_CAPTURE missing}"
XCLIP
chmod +x "$FAKE_XCLIP"

FAKE_OPENCODE="$TMP_DIR/opencode"
cat > "$FAKE_OPENCODE" <<'OPENCODE'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" -m "* ]]; then
  printf '%s\n' '{"type":"assistant.message.delta","text":"echo opencode-with-model"}'
else
  printf '%s\n' '{"type":"assistant.message.delta","text":"echo opencode-ok"}'
fi
OPENCODE
chmod +x "$FAKE_OPENCODE"

FAKE_CODEX="$TMP_DIR/codex"
cat > "$FAKE_CODEX" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --json "* ]]; then
  printf '%s\n' '{"event":"message.delta","text":"find . -type f -mtime -2 -size +100M -ls"}'
  printf '%s\n' '{"event":"message.stop"}'
else
  printf '%s\n' "find . -type f -mtime -2 -size +100M -ls"
fi
CODEX
chmod +x "$FAKE_CODEX"

CONFIG_FILE="$TMP_DIR/config.toml"
cat > "$CONFIG_FILE" <<CFG
provider = "codex"
model = ""
provider_cmd = "COUNTER_FILE=$COUNTER_FILE $FAKE_PROVIDER {PROMPT}"
timeout_seconds = "5"
max_retries = "1"
prompt_mode = "strict"

[profiles.fast]
provider_cmd = "COUNTER_FILE=$COUNTER_FILE $FAKE_PROVIDER {PROMPT}"
model = "fast-model"
shell = "fish"
max_retries = "2"
prompt_mode = "creative"
CFG
