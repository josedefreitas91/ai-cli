#!/usr/bin/env bash

usage() {
  cat <<USAGE
ai v$VERSION

Usage:
  ai "natural language request"
  ai --provider codex "create a git branch named feature/auth"
  ai doctor
  ai providers <list|check>
  ai config <get|set> <path> [value]
  ai replay <id|latest>
  ai init
  ai update
  ai uninstall
  ai completion <zsh|bash|fish>
  ai help [topic]
  ai profile

Options:
  -p, --provider <name>   Provider: codex | gemini | claude | opencode
  -m, --model <name>      Optional model name
  -c, --config <path>     TOML config path (default: $DEFAULT_CONFIG)
  --profile <name>        Config profile under [profiles.<name>]
  --prompt-mode <name>    Prompt style: strict | creative
  --ui <mode>             Output style: compact | pretty
  --meta                  Show metadata line in output
  --no-meta               Hide metadata line in output
  --shell <name>          Target shell: zsh | bash | fish | powershell
  --timeout <seconds>     Provider call timeout in seconds (default: 30)
  --max-retries <n>       Provider retries for transient failures (default: 1)

  Execution:
  --run                   Execute the suggested command
  --dry-run               Explicitly do not execute (default behavior)
    --confirm             Ask for confirmation before executing with --run

  Output:
  --explain               Add a short explanation of the suggested command
  --copy                  Copy suggested command to the OS clipboard
  --no-auto-copy          Disable automatic copy of suggested commands
  --quiet                 Minimal output (no spinner/explanation text)
  --no-color              Disable ANSI colors
  --json                  Output structured JSON

  History:
  --history               Show local generation history and exit
    --search <text>       Filter history rows by text (intent/command/provider/model/shell)
    --full                Show full rows without truncating columns
    --days <n>            Limit to the last N daily log files

  Misc:
  --raw                   Return raw provider JSON/JSONL output
    --ref <ref>           Used with 'update' (example: tags/v0.0.1)
    --scope <user|global> Used with 'update' install scope
    --force               Used with 'init' to overwrite existing config file
  --version               Show version
  --help, -h              Show this help
USAGE
}

show_help_topic() {
  local topic="${1:-}"
  case "$topic" in
    ""|general)
      usage
      ;;
    profile)
      cat <<HELP
Topic: profile

Use profiles to keep preset provider/model/shell settings:
  ai --profile <name> "your request"

Create or edit a profile interactively:
  ai profile
HELP
      ;;
    history)
      cat <<HELP
Topic: history

Show local history:
  ai --history

Show only the latest N daily files:
  ai --history --days 7

Show full rows without truncation:
  ai --history --full

Return history as JSON:
  ai --history --json

Filter history:
  ai --history --search "git"
HELP
      ;;
    replay)
      cat <<HELP
Topic: replay

Show a previous command:
  ai replay latest
  ai replay 3

Execute a previous command:
  ai --run replay latest
  ai --run --confirm replay 3
HELP
      ;;
    config)
      cat <<HELP
Topic: config

Read a config value:
  ai config get provider
  ai config get profiles.gemini.model

Set a config value:
  ai config set provider codex
  ai config set profiles.gemini.model ""
HELP
      ;;
    providers)
      cat <<HELP
Topic: providers

List provider CLIs:
  ai providers list

Check provider CLI and auth status (best effort):
  ai providers check
HELP
      ;;
    run)
      cat <<HELP
Topic: run

Generate only (default):
  ai "your request"

Execute generated command:
  ai --run "your request"

Ask before execution:
  ai --run --confirm "your request"
HELP
      ;;
    init)
      cat <<HELP
Topic: init

Create starter config with provider profiles:
  ai init

Overwrite existing config:
  ai init --force
HELP
      ;;
    completion)
      cat <<HELP
Topic: completion

Print shell completion script:
  ai completion zsh
  ai completion bash
  ai completion fish
HELP
      ;;
    update)
      cat <<HELP
Topic: update

Update ai-cli by running the remote installer:
  ai update
  ai update --ref tags/v0.0.1
  ai update --scope global
HELP
      ;;
    uninstall)
      cat <<HELP
Topic: uninstall

Run interactive uninstaller:
  ai uninstall
HELP
      ;;
    *)
      die "Unknown help topic '$topic'. Available topics: profile, history, run, replay, config, providers, init, update, completion, uninstall."
      ;;
  esac
}

print_pretty_rule() {
  local width="${1:-72}"
  printf '%*s\n' "$width" '' | tr ' ' '-'
}

print_generated_output() {
  local command="$1"
  local explanation="${2:-}"
  local meta_line=""
  local ui_mode="${UI_MODE:-compact}"
  local quiet_mode="${QUIET_MODE:-0}"
  local show_meta="${SHOW_META:-0}"
  local provider_value="${PROVIDER:-unknown}"
  local model_value="${MODEL:-<default>}"
  local profile_value="${PROFILE_NAME:-<none>}"
  local prompt_mode_value="${PROMPT_MODE:-strict}"

  if [[ "$ui_mode" == "pretty" && "$quiet_mode" -eq 0 ]]; then
    if [[ "$show_meta" -eq 1 ]]; then
      meta_line="provider: $provider_value | model: $model_value | profile: $profile_value | mode: $prompt_mode_value"
      printf '\n%s%s%s\n' "$C_CYAN" "$meta_line" "$C_RESET"
    else
      printf '\n'
    fi
    printf '%s%s%s\n' "$C_BOLD$C_CYAN" "Suggested command" "$C_RESET"
    print_pretty_rule 72
    printf '%s%s%s\n' "$C_GREEN" "$command" "$C_RESET"
    print_pretty_rule 72
    if [[ "$EXPLAIN_MODE" -eq 1 && -n "$explanation" ]]; then
      printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "Why" "$C_RESET"
      print_pretty_rule 72
      printf '%s\n' "$explanation"
      print_pretty_rule 72
    fi
    printf '\n'
    return 0
  fi

  printf '%s\n' "$command"
  if [[ "$EXPLAIN_MODE" -eq 1 && -n "$explanation" ]]; then
    printf 'Explanation: %s\n' "$explanation"
  fi
}

run_command_with_ui() {
  local command="$1"
  local rc
  local ui_mode="${UI_MODE:-compact}"
  local quiet_mode="${QUIET_MODE:-0}"

  if [[ "$ui_mode" == "pretty" && "$quiet_mode" -eq 0 ]]; then
    printf '%sExecuting...%s\n' "$C_CYAN" "$C_RESET" >&2
  fi

  set +e
  bash -lc "$command"
  rc=$?
  set -e

  if [[ "$ui_mode" == "pretty" && "$quiet_mode" -eq 0 ]]; then
    if [[ "$rc" -eq 0 ]]; then
      printf '%s[OK] Done%s\n' "$C_GREEN" "$C_RESET" >&2
    else
      printf '%s[FAIL] Exit %s%s\n' "$C_RED" "$rc" "$C_RESET" >&2
    fi
  fi
  return "$rc"
}
