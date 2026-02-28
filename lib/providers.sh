#!/usr/bin/env bash
# shellcheck disable=SC2034

extract_opencode_text() {
  local input="$1"
  local extracted

  extracted="$(printf '%s\n' "$input" | grep -Eo '"text"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | sed -E 's/^"text"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"
  if [[ -z "$extracted" ]]; then
    printf '%s' "$input"
    return 0
  fi

  printf '%s\n' "$extracted" | sed 's/\\"/"/g; s/\\\\/\\/g; s/\\n/\n/g'
}

resolve_provider_cmd_template() {
  local provider="$1"
  local model="$2"
  local raw_output_mode="${3:-0}"

  if [[ -n "${PROVIDER_CMD_EFFECTIVE:-}" ]]; then
    printf '%s' "$PROVIDER_CMD_EFFECTIVE"
    return 0
  fi

  case "$provider" in
    codex)
      if has_cmd codex; then
        local codex_json_flag=""
        if [[ "$raw_output_mode" -eq 1 ]]; then
          codex_json_flag=" --json"
        fi
        if [[ -n "$model" ]]; then
          printf 'codex exec --skip-git-repo-check%s --model %q {PROMPT}' "$codex_json_flag" "$model"
        else
          printf 'codex exec --skip-git-repo-check%s {PROMPT}' "$codex_json_flag"
        fi
        return 0
      fi
      die "Could not find 'codex' CLI."
      ;;
    gemini)
      if has_cmd gemini; then
        if [[ -n "$model" ]]; then
          printf 'gemini -m %q -p {PROMPT}' "$model"
        else
          printf 'gemini -p {PROMPT}'
        fi
        return 0
      fi
      die "Could not find 'gemini' CLI."
      ;;
    claude)
      if has_cmd claude; then
        if [[ -n "$model" ]]; then
          printf 'claude -m %q -p {PROMPT}' "$model"
        else
          printf 'claude -p {PROMPT}'
        fi
        return 0
      fi
      if has_cmd claude-code; then
        if [[ -n "$model" ]]; then
          printf 'claude-code -m %q -p {PROMPT}' "$model"
        else
          printf 'claude-code -p {PROMPT}'
        fi
        return 0
      fi
      die "Could not find 'claude' or 'claude-code' CLI."
      ;;
    opencode)
      if has_cmd opencode; then
        if [[ -n "$model" ]]; then
          printf 'opencode run -m %q --format json {PROMPT}' "$model"
        else
          printf 'opencode run --format json {PROMPT}'
        fi
        return 0
      fi
      die "Could not find 'opencode' CLI."
      ;;
    *)
      die "Unsupported provider: '$provider'. Use codex, gemini, claude, or opencode."
      ;;
  esac
}

run_command_with_timeout() {
  local cmd="$1"
  local timeout_seconds="$2"
  local stdout_file="$3"
  local stderr_file="$4"

  if [[ "$timeout_seconds" -le 0 ]] || ! has_cmd perl; then
    bash -lc "$cmd" >"$stdout_file" 2>"$stderr_file"
    return $?
  fi

  perl -e '
    my $timeout = shift @ARGV;
    my $pid = fork();
    if (!defined $pid) { exit 125; }
    if ($pid == 0) { exec @ARGV or exit 127; }

    my $timed_out = 0;
    local $SIG{ALRM} = sub {
      $timed_out = 1;
      kill "TERM", $pid;
      sleep 1;
      kill "KILL", $pid;
    };

    alarm $timeout;
    waitpid($pid, 0);
    alarm 0;

    if ($timed_out) { exit 124; }
    if ($? == -1) { exit 125; }
    if ($? & 127) { exit 128 + ($? & 127); }
    exit($? >> 8);
  ' "$timeout_seconds" bash -lc "$cmd" >"$stdout_file" 2>"$stderr_file"
  return $?
}

compact_error_message() {
  local text="$1"
  local max_len=280
  text="$(trim "$text")"
  text="${text//$'\n'/ }"
  text="${text//$'\r'/ }"
  text="$(printf '%s' "$text" | tr -s ' ')"
  if (( ${#text} > max_len )); then
    printf '%s...' "${text:0:$((max_len - 3))}"
    return 0
  fi
  printf '%s' "$text"
}

parse_bool_setting() {
  local value="$1"
  local default_value="$2"
  local normalized

  if [[ -z "$value" ]]; then
    printf '%s' "$default_value"
    return 0
  fi

  normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    1|true|yes|on) printf '1' ;;
    0|false|no|off) printf '0' ;;
    *)
      die "Invalid boolean value '$value'. Use true/false, yes/no, on/off, or 1/0."
      ;;
  esac
}

summarize_provider_error() {
  local stderr_text="$1"
  local stdout_text="$2"
  local combined detail line

  combined="$(printf '%s\n%s\n' "$stderr_text" "$stdout_text")"

  detail="$(printf '%s\n' "$combined" | grep -Eo '"detail"[[:space:]]*:[[:space:]]*"[^"]+"' | tail -n 1 | sed -E 's/^"detail"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  if [[ -n "$detail" ]]; then
    compact_error_message "$detail"
    return 0
  fi

  line="$(printf '%s\n' "$combined" | grep -E '^[[:space:]]*ERROR:' | tail -n 1 | sed -E 's/^[[:space:]]*ERROR:[[:space:]]*//')"
  if [[ -n "$line" ]]; then
    compact_error_message "$line"
    return 0
  fi

  line="$(printf '%s\n' "$combined" | grep -Ei '(model.*not (supported|found)|not supported|not found|authentication|unauthorized|forbidden)' | tail -n 1)"
  if [[ -n "$line" ]]; then
    compact_error_message "$line"
    return 0
  fi

  line="$(printf '%s\n' "$stderr_text" | awk 'NF { last=$0 } END { print last }')"
  if [[ -n "$line" ]]; then
    compact_error_message "$line"
    return 0
  fi

  line="$(printf '%s\n' "$stdout_text" | awk 'NF { last=$0 } END { print last }')"
  if [[ -n "$line" ]]; then
    compact_error_message "$line"
    return 0
  fi

  printf '%s' "Unknown provider error"
}

run_provider_prompt() {
  local prompt_text="$1"
  local purpose="$2"

  local escaped_prompt final_cmd out_file err_file
  escaped_prompt="$(printf '%q' "$prompt_text")"
  final_cmd="${TEMPLATE//\{PROMPT\}/$escaped_prompt}"

  local attempt=1
  local rc=0
  LAST_PROVIDER_ERROR=""
  LAST_PROVIDER_OUTPUT=""

  while (( attempt <= MAX_RETRIES )); do
    out_file="$(mktemp)"
    err_file="$(mktemp)"

    local worker_pid spinner_pid
    set +e
    run_command_with_timeout "$final_cmd" "$TIMEOUT_SECONDS" "$out_file" "$err_file" &
    worker_pid=$!

    spinner_pid=""
    if should_show_spinner; then
      run_loading_spinner "$worker_pid" &
      spinner_pid=$!
    fi

    wait "$worker_pid"
    rc=$?

    if [[ -n "$spinner_pid" ]]; then
      wait "$spinner_pid" 2>/dev/null || true
    fi
    set -e
    if [[ "$rc" -eq 0 ]]; then
      LAST_PROVIDER_OUTPUT="$(cat "$out_file")"
      rm -f "$out_file" "$err_file"
      return 0
    fi

    if [[ "$rc" -eq 124 ]]; then
      LAST_PROVIDER_ERROR="Timed out after ${TIMEOUT_SECONDS}s"
    else
      LAST_PROVIDER_ERROR="$(summarize_provider_error "$(cat "$err_file")" "$(cat "$out_file")")"
    fi

    rm -f "$out_file" "$err_file"

    if (( attempt == MAX_RETRIES )); then
      break
    fi
    attempt=$((attempt + 1))
  done

  die "Provider '$PROVIDER' failed for $purpose after $MAX_RETRIES attempt(s): $LAST_PROVIDER_ERROR"
}

provider_auth_status() {
  local provider="$1"
  local out_file err_file rc
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  set +e
  case "$provider" in
    codex)
      run_command_with_timeout 'codex whoami' 4 "$out_file" "$err_file"
      rc=$?
      if [[ "${rc:-0}" -eq 0 ]]; then
        set -e
        rm -f "$out_file" "$err_file"
        printf '%s' "authenticated"
        return 0
      fi
      run_command_with_timeout 'codex auth status' 4 "$out_file" "$err_file"
      rc=$?
      ;;
    gemini)
      run_command_with_timeout 'gemini auth status' 4 "$out_file" "$err_file"
      rc=$?
      ;;
    claude)
      if has_cmd claude; then
        run_command_with_timeout 'claude auth status' 4 "$out_file" "$err_file"
        rc=$?
      else
        run_command_with_timeout 'claude-code auth status' 4 "$out_file" "$err_file"
        rc=$?
      fi
      ;;
    opencode)
      run_command_with_timeout 'opencode whoami' 4 "$out_file" "$err_file"
      rc=$?
      if [[ "${rc:-0}" -eq 0 ]]; then
        set -e
        rm -f "$out_file" "$err_file"
        printf '%s' "authenticated"
        return 0
      fi
      run_command_with_timeout 'opencode auth status' 4 "$out_file" "$err_file"
      rc=$?
      ;;
  esac
  set -e

  if [[ "${rc:-0}" -eq 0 ]]; then
    rm -f "$out_file" "$err_file"
    printf '%s' "authenticated"
    return 0
  fi

  rm -f "$out_file" "$err_file"
  printf '%s' "unknown"
}
