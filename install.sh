#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
BIN_SRC="$SCRIPT_DIR/bin/ai"
LIB_DIR_SRC="$SCRIPT_DIR/lib"
CONFIG_DIR_SRC="$SCRIPT_DIR/config"
TOML_EXAMPLE="$CONFIG_DIR_SRC/config.toml.example"
CONFIG_DIR="$HOME/.config/ai-cli"
CONFIG_TARGET="$CONFIG_DIR/config.toml"

# GitHub source defaults used by bootstrap mode (when local source files are missing).
# Update these two values for your repository.
GITHUB_OWNER="${AI_CLI_GITHUB_OWNER:-josedefreitas91}"
GITHUB_REPO="${AI_CLI_GITHUB_REPO:-ai-cli}"
REPO_DEFAULT="${GITHUB_OWNER}/${GITHUB_REPO}"
REPO="${AI_CLI_REPO:-$REPO_DEFAULT}"
REF="latest"

usage() {
  cat <<USAGE
ai-cli installer

Usage:
  ./install.sh [--repo <owner/repo>] [--ref <latest|tags/vX.Y.Z|heads/main>] [install options]

Bootstrap options:
  --repo <owner/repo>      GitHub repo to download from if local sources are missing
  --ref <ref>              Release ref to install when bootstrapping
                            default: latest
                            examples: latest, tags/v0.0.1, heads/main

Install options:
  --scope <user|global>    Choose default install scope
  --user                   Alias for --scope user
  --global                 Alias for --scope global
  -h, --help               Show help

Behavior:
  - If run from repository root (bin/lib/config present), installs local source.
  - Otherwise, downloads source from GitHub releases (latest by default) and runs install.
USAGE
}

prompt_default() {
  local question="$1"
  local default="$2"
  local answer
  if [[ ! -t 0 ]]; then
    printf '%s' "$default"
    return 0
  fi
  read -r -p "$question [$default]: " answer
  printf '%s' "${answer:-$default}"
}

prompt_yes_no() {
  local question="$1"
  local default="${2:-Y}"
  local answer
  if [[ ! -t 0 ]]; then
    case "$default" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi
  read -r -p "$question [$default]: " answer
  answer="${answer:-$default}"
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

toml_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

resolve_latest_tag() {
  local repo="$1"
  local api_url tag
  api_url="https://api.github.com/repos/${repo}/releases/latest"
  tag="$(curl -fsSL "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "$tag" ]]; then
    echo "Error: could not resolve latest release tag from $api_url" >&2
    exit 1
  fi
  printf '%s\n' "$tag"
}

bootstrap_and_reexec() {
  local repo="$1"
  local ref="$2"
  shift 2
  local -a passthrough=("$@")
  local archive_ref archive_url tmp_dir src_dir

  if [[ "$ref" == "latest" ]]; then
    archive_ref="tags/$(resolve_latest_tag "$repo")"
  else
    archive_ref="$ref"
  fi

  archive_url="https://github.com/${repo}/archive/refs/${archive_ref}.tar.gz"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  echo "Downloading ${repo} (${archive_ref})..."
  curl -fsSL "$archive_url" | tar -xz -C "$tmp_dir"

  src_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "$src_dir" || ! -f "$src_dir/install.sh" ]]; then
    echo "Error: install.sh not found in downloaded archive." >&2
    exit 1
  fi

  chmod +x "$src_dir/install.sh"
  if [[ "${#passthrough[@]}" -gt 0 ]]; then
    exec "$src_dir/install.sh" --repo "$repo" --ref "$archive_ref" "${passthrough[@]}"
  else
    exec "$src_dir/install.sh" --repo "$repo" --ref "$archive_ref"
  fi
}

# Parse bootstrap options first and keep install args for later.
declare -a INSTALL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -lt 2 ]] && { echo "Error: missing value for --repo" >&2; exit 1; }
      REPO="$2"
      shift 2
      ;;
    --ref)
      [[ $# -lt 2 ]] && { echo "Error: missing value for --ref" >&2; exit 1; }
      REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      INSTALL_ARGS+=("$1")
      shift
      ;;
  esac
done

# If local sources are not present, bootstrap from GitHub and re-exec.
if [[ ! -x "$BIN_SRC" || ! -d "$LIB_DIR_SRC" || ! -f "$TOML_EXAMPLE" ]]; then
  if [[ "${#INSTALL_ARGS[@]}" -gt 0 ]]; then
    bootstrap_and_reexec "$REPO" "$REF" "${INSTALL_ARGS[@]}"
  else
    bootstrap_and_reexec "$REPO" "$REF"
  fi
fi

# From this point, install local source.
if [[ "${#INSTALL_ARGS[@]}" -gt 0 ]]; then
  set -- "${INSTALL_ARGS[@]}"
else
  set --
fi

SCOPE="user"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      [[ $# -lt 2 ]] && { echo "Error: missing value for --scope" >&2; exit 1; }
      SCOPE="$2"
      shift 2
      ;;
    --user)
      SCOPE="user"
      shift
      ;;
    --global)
      SCOPE="global"
      shift
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$SCOPE" in
  user|global) ;;
  *)
    echo "Error: invalid scope '$SCOPE'. Use user or global." >&2
    exit 1
    ;;
esac

DEFAULT_INSTALL_DIR="$HOME/.local/bin"
DEFAULT_APP_HOME="$HOME/.local/share/ai-cli"
if [[ "$SCOPE" == "global" ]]; then
  DEFAULT_INSTALL_DIR="/usr/local/bin"
  DEFAULT_APP_HOME="/usr/local/share/ai-cli"
fi

echo "ai-cli installer"
echo

INSTALL_DIR="$(prompt_default "Command installation directory" "$DEFAULT_INSTALL_DIR")"
APP_HOME="$(prompt_default "Application home directory" "$DEFAULT_APP_HOME")"
REUSE_EXISTING_CONFIG=0
if [[ -f "$CONFIG_TARGET" ]]; then
  if prompt_yes_no "Existing config found at $CONFIG_TARGET. Keep it?" "Y"; then
    REUSE_EXISTING_CONFIG=1
  fi
fi

echo
if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  if [[ "$SCOPE" == "global" ]]; then
    echo "Error: cannot write to $INSTALL_DIR. Re-run with sudo or use --scope user." >&2
  else
    echo "Error: cannot write to $INSTALL_DIR." >&2
  fi
  exit 1
fi
if ! mkdir -p "$APP_HOME/bin" "$APP_HOME/lib" "$APP_HOME/config" 2>/dev/null; then
  if [[ "$SCOPE" == "global" ]]; then
    echo "Error: cannot write to $APP_HOME. Re-run with sudo or use --scope user." >&2
  else
    echo "Error: cannot write to $APP_HOME." >&2
  fi
  exit 1
fi
mkdir -p "$CONFIG_DIR"

cp "$BIN_SRC" "$APP_HOME/bin/ai"
chmod +x "$APP_HOME/bin/ai"
cp "$LIB_DIR_SRC"/*.sh "$APP_HOME/lib/"
chmod +x "$APP_HOME/lib"/*.sh
cp "$TOML_EXAMPLE" "$APP_HOME/config/config.toml.example"

TARGET_BIN="$INSTALL_DIR/ai"
ln -sfn "$APP_HOME/bin/ai" "$TARGET_BIN"

if [[ "$REUSE_EXISTING_CONFIG" -eq 0 ]]; then
  PROVIDER="$(prompt_default "Default provider (codex/gemini/claude/opencode)" "codex")"
  MODEL="$(prompt_default "Default model (optional)" "")"
  SHELL_TARGET="$(prompt_default "Default shell (zsh/bash/fish/powershell)" "zsh")"
  TIMEOUT_SECONDS="$(prompt_default "Default timeout seconds" "30")"
  MAX_RETRIES="$(prompt_default "Default max retries" "1")"
  PROMPT_MODE="$(prompt_default "Default prompt mode (strict/creative)" "strict")"
  UI_MODE="$(prompt_default "Default UI mode (compact/pretty)" "compact")"
  SHOW_META="$(prompt_default "Show metadata by default? (0/1)" "0")"
  if [[ -t 0 ]]; then
    read -r -p "Custom provider_cmd (optional): " PROVIDER_CMD
  else
    PROVIDER_CMD=""
  fi
  echo

  case "$PROMPT_MODE" in
    strict|creative) ;;
    *)
      echo "Error: invalid prompt mode '$PROMPT_MODE'. Use strict or creative." >&2
      exit 1
      ;;
  esac
  case "$PROVIDER" in
    codex|gemini|claude|opencode) ;;
    *)
      echo "Error: invalid provider '$PROVIDER'. Use codex, gemini, claude, or opencode." >&2
      exit 1
      ;;
  esac
  case "$UI_MODE" in
    compact|pretty) ;;
    *)
      echo "Error: invalid UI mode '$UI_MODE'. Use compact or pretty." >&2
      exit 1
      ;;
  esac
  case "$SHOW_META" in
    0|1) ;;
    *)
      echo "Error: invalid show_meta '$SHOW_META'. Use 0 or 1." >&2
      exit 1
      ;;
  esac

  cp "$TOML_EXAMPLE" "$CONFIG_TARGET"

  cat > "$CONFIG_TARGET" <<CONFIG
provider = "$(toml_escape "$PROVIDER")"
model = "$(toml_escape "$MODEL")"
provider_cmd = "$(toml_escape "$PROVIDER_CMD")"
shell = "$(toml_escape "$SHELL_TARGET")"
timeout_seconds = "$(toml_escape "$TIMEOUT_SECONDS")"
max_retries = "$(toml_escape "$MAX_RETRIES")"
prompt_mode = "$(toml_escape "$PROMPT_MODE")"
ui = "$(toml_escape "$UI_MODE")"
show_meta = "$(toml_escape "$SHOW_META")"
CONFIG
fi

echo "Installation completed."
echo "- Launcher: $TARGET_BIN"
echo "- App home: $APP_HOME"
echo "- Runtime libs: $APP_HOME/lib/*.sh"
echo "- Config: $CONFIG_TARGET"
if [[ "$REUSE_EXISTING_CONFIG" -eq 1 ]]; then
  echo "- Config action: reused existing file"
else
  echo "- Config action: wrote installer values"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    echo "- PATH: OK ($INSTALL_DIR is already in PATH)"
    ;;
  *)
    echo "- PATH: add this line to ~/.zshrc"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
esac

echo
echo "Try:"
echo "  ai \"list large files\""
