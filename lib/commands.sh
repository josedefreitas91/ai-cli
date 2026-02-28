#!/usr/bin/env bash

is_dangerous_command() {
  local cmd="$1"
  if printf '%s\n' "$cmd" | grep -Eiq '(^|[[:space:]])rm[[:space:]]+-rf([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s\n' "$cmd" | grep -Eiq 'git[[:space:]]+reset[[:space:]]+--hard'; then
    return 0
  fi
  if printf '%s\n' "$cmd" | grep -Eiq '(^|[;&|[:space:]])dd[[:space:]]+if='; then
    return 0
  fi
  if printf '%s\n' "$cmd" | grep -Eiq 'chmod[[:space:]]+-R[[:space:]]+777'; then
    return 0
  fi
  if printf '%s\n' "$cmd" | grep -Eiq '(^|[[:space:]])mkfs([[:space:]]|\.)'; then
    return 0
  fi
  return 1
}

prompt_confirm() {
  local prompt_text="${1:-Run command? [y/N] }"
  local answer=""
  if ! read -r -p "$prompt_text" answer; then
    return 1
  fi
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

build_prompt() {
  local intent="$1"
  local target_shell="$2"
  local prompt_mode="$3"
  local os_name cwd_value in_git_repo has_rg has_grep

  os_name="$(detect_os)"
  cwd_value="$(pwd)"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_git_repo="yes"
  else
    in_git_repo="no"
  fi
  if has_cmd rg; then
    has_rg="yes"
  else
    has_rg="no"
  fi
  if has_cmd grep; then
    has_grep="yes"
  else
    has_grep="no"
  fi

  cat <<PROMPT
You are a CLI command generator.

Return exactly ONE executable shell command for this environment:
- OS: $os_name
- Shell: $target_shell
- Target shell: $target_shell
- CWD: $cwd_value
- In git repo: $in_git_repo
- rg available: $has_rg
- grep available: $has_grep
- Prompt mode: $prompt_mode

Global rules:
- Output only the command. No markdown. No explanations.
- Must be valid for the target shell.
- Keep it to a single line.
- Prefer safe, non-destructive commands unless explicitly requested.
- Do not output placeholders like <file>, <path>, YOUR_VALUE.
- Quote and escape paths/arguments safely.
- Avoid destructive commands (rm -rf, reset --hard, mkfs, etc.) unless explicitly requested.
PROMPT

  case "$prompt_mode" in
    strict)
      cat <<PROMPT

Mode-specific rules (strict):
- If ambiguous, choose the safest useful command.
- Keep the command simple and predictable.
- Prefer fast tools when available (e.g., rg over grep).
PROMPT
      ;;
    creative)
      cat <<PROMPT

Mode-specific rules (creative):
- You may use concise pipelines/flags that improve usability.
- Prefer practical defaults and readable output for humans.
- Prefer fast tools when available (e.g., rg over grep).
- Stay safe; never choose destructive commands unless explicitly requested.
- Prefer commands that are easy to copy/paste and run immediately in this OS/shell.
- On macOS/Linux, favor common built-ins and widely available tools before niche utilities.
- Include human-readable flags when useful (for example, readable sizes or limited result counts).
- Avoid brittle one-liners that depend on uncommon shell-specific behavior.
PROMPT
      ;;
  esac

  cat <<PROMPT

User intent:
$intent
PROMPT
}

build_explain_prompt() {
  local command="$1"
  local target_shell="$2"
  cat <<PROMPT
Explain this shell command in one short sentence.

Rules:
- Keep it concise.
- No markdown.
- Mention the key effect only.
- Target shell: $target_shell

Command:
$command
PROMPT
}

run_doctor() {
  local config_path="$1"
  local profile_name="$2"

  load_config_values "$config_path" "$profile_name"

  local provider_effective model_effective shell_effective prompt_mode_effective ui_effective show_meta_effective
  provider_effective="${PROVIDER_ARG:-${PROVIDER_CFG:-codex}}"
  if [[ "${MODEL_ARG_SET:-0}" -eq 1 ]]; then
    model_effective="$MODEL_ARG"
  else
    model_effective="${MODEL_CFG:-}"
  fi
  shell_effective="${TARGET_SHELL_ARG:-${TARGET_SHELL_CFG:-zsh}}"
  prompt_mode_effective="${PROMPT_MODE_ARG:-${PROMPT_MODE_CFG:-strict}}"
  ui_effective="${UI_MODE_ARG:-${UI_MODE_CFG:-compact}}"
  show_meta_effective="$(parse_bool_setting "${SHOW_META_ARG:-${SHOW_META_CFG:-0}}" "0")"

  echo "ai doctor"
  if [[ -f "$config_path" ]]; then
    echo "- Config: $config_path (found)"
  else
    echo "- Config: $config_path (missing)"
  fi
  if [[ -n "$profile_name" ]]; then
    echo "- Profile: $profile_name"
  else
    echo "- Profile: (none)"
  fi
  local os_name
  os_name="$(detect_os)"

  echo "- OS: $os_name"
  echo "- Effective provider: $provider_effective"
  echo "- Effective model: ${model_effective:-<empty>}"
  echo "- Effective shell: $shell_effective"
  echo "- Effective prompt mode: $prompt_mode_effective"
  echo "- Effective ui: $ui_effective"
  echo "- Effective show_meta: $show_meta_effective"

  if has_cmd codex; then echo "- codex CLI: OK"; else echo "- codex CLI: MISSING"; fi
  if has_cmd gemini; then echo "- gemini CLI: OK"; else echo "- gemini CLI: MISSING"; fi
  if has_cmd claude || has_cmd claude-code; then echo "- claude CLI: OK"; else echo "- claude CLI: MISSING"; fi
  if has_cmd opencode; then echo "- opencode CLI: OK"; else echo "- opencode CLI: MISSING"; fi
  case "$os_name" in
    Darwin)
      if has_cmd pbcopy; then echo "- clipboard pbcopy: OK"; else echo "- clipboard pbcopy: MISSING"; fi
      ;;
    Linux)
      if has_cmd wl-copy; then echo "- clipboard wl-copy: OK"; else echo "- clipboard wl-copy: MISSING"; fi
      if has_cmd xclip; then echo "- clipboard xclip: OK"; else echo "- clipboard xclip: MISSING"; fi
      if has_cmd xsel; then echo "- clipboard xsel: OK"; else echo "- clipboard xsel: MISSING"; fi
      ;;
    *)
      echo "- clipboard: unsupported OS for --copy"
      ;;
  esac
}

run_providers() {
  local action="$1"
  local provider installed auth_status

  case "$action" in
    list)
      echo "Providers"
      for provider in codex gemini claude opencode; do
        installed="missing"
        if [[ "$provider" == "claude" ]]; then
          if has_cmd claude || has_cmd claude-code; then
            installed="installed"
          fi
        else
          if has_cmd "$provider"; then
            installed="installed"
          fi
        fi
        printf -- "- %s: %s\n" "$provider" "$installed"
      done
      ;;
    check)
      echo "Provider checks"
      for provider in codex gemini claude opencode; do
        installed="missing"
        if [[ "$provider" == "claude" ]]; then
          if has_cmd claude || has_cmd claude-code; then
            installed="installed"
          fi
        else
          if has_cmd "$provider"; then
            installed="installed"
          fi
        fi
        if [[ "$installed" == "installed" ]]; then
          auth_status="$(provider_auth_status "$provider")"
        else
          auth_status="not-installed"
        fi
        printf -- "- %s: cli=%s auth=%s\n" "$provider" "$installed" "$auth_status"
      done
      ;;
    *)
      die "Usage: ai providers <list|check>"
      ;;
  esac
}

run_replay() {
  local ref="$1"
  local replay_command

  replay_command="$(get_history_command_by_ref "$ref" || true)"
  [[ -z "$replay_command" ]] && die "History entry not found: $ref"

  if [[ "$RUN_COMMAND" -eq 1 ]]; then
    if is_dangerous_command "$replay_command"; then
      CONFIRM_RUN=1
      warn "this replay command matches dangerous patterns and requires confirmation."
    fi
    if [[ "$CONFIRM_RUN" -eq 0 ]]; then
      CONFIRM_RUN=1
    fi
    if ! prompt_confirm "Run replayed command? [y/N] "; then
      die "Replay execution requires confirmation."
    fi
    run_command_with_ui "$replay_command"
    exit $?
  fi

  print_generated_output "$replay_command" ""
}

run_completion() {
  local shell_name="$1"

  case "$shell_name" in
    zsh)
      cat <<'ZSH'
#compdef ai

_ai() {
  local -a opts
  opts=(
    '--provider[Provider]:provider:(codex gemini claude opencode)'
    '--model[Model name]:model:_default'
    '--config[Config path]:path:_files'
    '--profile[Profile name]:profile:_default'
    '--prompt-mode[Prompt style]:mode:(strict creative)'
    '--ui[Output style]:mode:(compact pretty)'
    '--meta[Show metadata line]'
    '--no-meta[Hide metadata line]'
    '--shell[Target shell]:shell:(zsh bash fish powershell)'
    '--timeout[Timeout seconds]:seconds:_default'
    '--max-retries[Retry count]:count:_default'
    '--run[Execute suggested command]'
    '--dry-run[Do not execute suggested command]'
    '--confirm[Ask before executing with --run]'
    '--explain[Show explanation]'
    '--copy[Copy command to clipboard]'
    '--no-auto-copy[Disable automatic copy]'
    '--quiet[Minimal output]'
    '--no-color[Disable colors]'
    '--json[JSON output]'
    '--history[Show history]'
    '--search[Filter history rows]:text:_default'
    '--full[Used with --history to show full rows]'
    '--days[History days]:days:_default'
    '--raw[Raw provider output]'
    '--ref[Update release ref]:ref:_default'
    '--scope[Update install scope]:scope:(user global)'
    '--force[Force overwrite for init]'
    '--version[Show version]'
    '--help[Show help]'
  )

  _arguments -s -S $opts \
    '1:command:(help doctor profile replay config providers init update uninstall completion)' \
    '2:arg:(zsh bash fish)'
}

_ai "$@"
ZSH
      ;;
    bash)
      cat <<'BASH'
_ai_completions() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  case "$prev" in
    --provider) COMPREPLY=( $(compgen -W "codex gemini claude opencode" -- "$cur") ); return 0 ;;
    --shell) COMPREPLY=( $(compgen -W "zsh bash fish powershell" -- "$cur") ); return 0 ;;
    --scope) COMPREPLY=( $(compgen -W "user global" -- "$cur") ); return 0 ;;
    --prompt-mode) COMPREPLY=( $(compgen -W "strict creative" -- "$cur") ); return 0 ;;
    --ui) COMPREPLY=( $(compgen -W "compact pretty" -- "$cur") ); return 0 ;;
    completion) COMPREPLY=( $(compgen -W "zsh bash fish" -- "$cur") ); return 0 ;;
    providers) COMPREPLY=( $(compgen -W "list check" -- "$cur") ); return 0 ;;
    config) COMPREPLY=( $(compgen -W "get set" -- "$cur") ); return 0 ;;
  esac

  COMPREPLY=( $(compgen -W "--provider --model --config --profile --prompt-mode --ui --meta --no-meta --shell --timeout --max-retries --run --dry-run --confirm --explain --copy --no-auto-copy --quiet --no-color --json --history --search --full --days --raw --ref --scope --force --version --help doctor help profile replay config providers init update uninstall completion" -- "$cur") )
}

complete -F _ai_completions ai
BASH
      ;;
    fish)
      cat <<'FISH'
complete -c ai -f
complete -c ai -n "__fish_use_subcommand" -a "help doctor profile replay config providers init update uninstall completion"
complete -c ai -l provider -a "codex gemini claude opencode"
complete -c ai -l model
complete -c ai -l config -r
complete -c ai -l profile
complete -c ai -l prompt-mode -a "strict creative"
complete -c ai -l ui -a "compact pretty"
complete -c ai -l meta
complete -c ai -l no-meta
complete -c ai -l shell -a "zsh bash fish powershell"
complete -c ai -l timeout
complete -c ai -l max-retries
complete -c ai -l run
complete -c ai -l dry-run
complete -c ai -l confirm
complete -c ai -l explain
complete -c ai -l copy
complete -c ai -l no-auto-copy
complete -c ai -l quiet
complete -c ai -l no-color
complete -c ai -l json
complete -c ai -l history
complete -c ai -l search
complete -c ai -l full
complete -c ai -l days
complete -c ai -l raw
complete -c ai -l ref
complete -c ai -l scope -a "user global"
complete -c ai -l force
complete -c ai -l version
complete -c ai -s h -l help
complete -c ai -n "__fish_seen_subcommand_from completion" -a "zsh bash fish"
complete -c ai -n "__fish_seen_subcommand_from providers" -a "list check"
complete -c ai -n "__fish_seen_subcommand_from config" -a "get set"
FISH
      ;;
    *)
      die "Unsupported completion shell '$shell_name'. Use zsh, bash, or fish."
      ;;
  esac
}

run_update() {
  local ref="${1:-}"
  local scope="${2:-}"
  local repo owner_name repo_name install_url latest_api_url latest_tag target_tag
  local local_version normalized_target_version normalized_local_version
  local should_check_latest=0
  local install_args=()

  owner_name="${AI_CLI_GITHUB_OWNER:-josedefreitas91}"
  repo_name="${AI_CLI_GITHUB_REPO:-ai-cli}"
  repo="${AI_CLI_REPO:-${owner_name}/${repo_name}}"
  install_url="https://raw.githubusercontent.com/${repo}/main/install.sh"

  if [[ -n "$scope" ]]; then
    case "$scope" in
      user|global) ;;
      *) die "Unsupported update scope '$scope'. Use user or global." ;;
    esac
  fi

  if [[ -z "$ref" || "$ref" == "latest" ]]; then
    should_check_latest=1
  fi

  if [[ "$should_check_latest" -eq 1 ]]; then
    latest_api_url="https://api.github.com/repos/${repo}/releases/latest"
    latest_tag="$(curl -fsSL "$latest_api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [[ -z "$latest_tag" ]] && die "Could not resolve latest release tag for ${repo}."

    normalized_local_version="${VERSION#v}"
    normalized_target_version="${latest_tag#v}"
    if [[ "$normalized_local_version" == "$normalized_target_version" ]]; then
      echo "ai-cli is already up to date (v$normalized_local_version)."
      return 0
    fi

    ref="tags/$latest_tag"
  elif [[ "$ref" == tags/* ]]; then
    target_tag="${ref#tags/}"
    normalized_local_version="${VERSION#v}"
    normalized_target_version="${target_tag#v}"
    if [[ "$normalized_local_version" == "$normalized_target_version" ]]; then
      echo "ai-cli is already at requested version (v$normalized_local_version)."
      return 0
    fi
  fi

  install_args+=(--repo "$repo")
  if [[ -n "$ref" ]]; then
    install_args+=(--ref "$ref")
  fi
  if [[ -n "$scope" ]]; then
    install_args+=(--scope "$scope")
  fi

  has_cmd curl || die "Could not find 'curl' required for update."
  local_version="${VERSION#v}"
  echo "Updating ai-cli from ${repo} (current: v${local_version})..."
  curl -fsSL "$install_url" | bash -s -- "${install_args[@]}"
}

run_uninstall() {
  local config_dir config_file history_dir
  local detected_bin default_install_dir default_app_home resolved_bin candidate_app_home
  local install_dir app_home target_bin

  config_dir="$HOME/.config/ai-cli"
  config_file="$config_dir/config.toml"
  history_dir="$config_dir/history"

  resolve_path() {
    local p="$1"
    if [[ -z "$p" ]]; then
      return 1
    fi
    if command -v realpath >/dev/null 2>&1; then
      realpath "$p" 2>/dev/null || return 1
      return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null || return 1
      return 0
    fi
    printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
  }

  prompt_yes_no() {
    local question="$1"
    local default="${2:-N}"
    local answer
    read -r -p "$question [$default]: " answer
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  }

  echo "ai-cli uninstaller"
  echo

  detected_bin=""
  if command -v ai >/dev/null 2>&1; then
    detected_bin="$(command -v ai)"
  fi

  default_install_dir="$HOME/.local/bin"
  if [[ -n "$detected_bin" ]]; then
    default_install_dir="$(dirname "$detected_bin")"
  fi

  default_app_home="$HOME/.local/share/ai-cli"
  if [[ -n "$detected_bin" ]]; then
    resolved_bin="$(resolve_path "$detected_bin" || true)"
    if [[ "$resolved_bin" == */bin/ai ]]; then
      candidate_app_home="$(dirname "$(dirname "$resolved_bin")")"
      if [[ -f "$candidate_app_home/lib/config.sh" ]]; then
        default_app_home="$candidate_app_home"
      fi
    fi
  fi

  install_dir="$(prompt_default "Command installation directory" "$default_install_dir")"
  app_home="$(prompt_default "Application home directory" "$default_app_home")"
  target_bin="$install_dir/ai"

  echo
  if [[ -e "$target_bin" || -L "$target_bin" ]]; then
    rm -f "$target_bin"
    echo "- Removed launcher: $target_bin"
  else
    echo "- Launcher not found at: $target_bin"
  fi

  if prompt_yes_no "Remove app home directory ($app_home)?" "Y"; then
    if [[ -d "$app_home" ]]; then
      rm -rf "$app_home"
      echo "- Removed app home: $app_home"
    else
      echo "- App home not found: $app_home"
    fi
  fi

  if prompt_yes_no "Remove config file ($config_file)?" "N"; then
    if [[ -f "$config_file" ]]; then
      rm -f "$config_file"
      echo "- Removed config file: $config_file"
    else
      echo "- Config file not found: $config_file"
    fi
  fi

  if prompt_yes_no "Remove history directory ($history_dir)?" "N"; then
    if [[ -d "$history_dir" ]]; then
      rm -rf "$history_dir"
      echo "- Removed history directory: $history_dir"
    else
      echo "- History directory not found: $history_dir"
    fi
  fi

  if prompt_yes_no "Remove remaining config directory if empty ($config_dir)?" "Y"; then
    if [[ -d "$config_dir" ]]; then
      rmdir "$config_dir" 2>/dev/null || true
      if [[ -d "$config_dir" ]]; then
        echo "- Config directory is not empty, keeping: $config_dir"
      else
        echo "- Removed empty config directory: $config_dir"
      fi
    fi
  fi

  echo
  echo "Uninstall completed."
}
