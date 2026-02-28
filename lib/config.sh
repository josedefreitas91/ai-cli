#!/usr/bin/env bash
# shellcheck disable=SC2034

toml_get_string() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 1

  awk -v key="$key" '
    BEGIN { in_section = 0 }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*\[/ { in_section = 1; next }
    {
      if (!in_section) {
        pattern = "^[[:space:]]*" key "[[:space:]]*=[[:space:]]*\".*\"[[:space:]]*$"
        if ($0 ~ pattern) {
          line = $0
          sub(/^[[:space:]]*[^=]*=[[:space:]]*\"/, "", line)
          sub(/\"[[:space:]]*$/, "", line)
          print line
          exit
        }
      }
    }
  ' "$file" | sed 's/\\\"/"/g; s/\\\\/\\/g'
}

toml_get_section_string() {
  local file="$1"
  local section="$2"
  local key="$3"

  [[ -f "$file" ]] || return 1

  awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^[[:space:]]*\[/ {
      in_section = ($0 == "[" section "]")
    }
    {
      if (in_section) {
        pattern = "^[[:space:]]*" key "[[:space:]]*=[[:space:]]*\".*\"[[:space:]]*$"
        if ($0 ~ pattern) {
          line = $0
          sub(/^[[:space:]]*[^=]*=[[:space:]]*\"/, "", line)
          sub(/\"[[:space:]]*$/, "", line)
          print line
          exit
        }
      }
    }
  ' "$file" | sed 's/\\\"/"/g; s/\\\\/\\/g'
}

toml_section_has_key() {
  local file="$1"
  local section="$2"
  local key="$3"

  [[ -f "$file" ]] || return 1

  awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^[[:space:]]*\[/ {
      in_section = ($0 == "[" section "]")
    }
    {
      if (in_section) {
        pattern = "^[[:space:]]*" key "[[:space:]]*="
        if ($0 ~ pattern) {
          found = 1
          exit 0
        }
      }
    }
    END {
      if (found == 1) {
        exit 0
      }
      exit 1
    }
  ' "$file"
}

toml_root_has_key() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 1

  awk -v key="$key" '
    BEGIN { in_root = 1 }
    /^[[:space:]]*\[/ {
      in_root = 0
    }
    {
      if (in_root) {
        pattern = "^[[:space:]]*" key "[[:space:]]*="
        if ($0 ~ pattern) {
          found = 1
          exit 0
        }
      }
    }
    END {
      if (found == 1) {
        exit 0
      }
      exit 1
    }
  ' "$file"
}

load_config_values() {
  local config_path="$1"
  local profile_name="$2"

  PROVIDER_CFG=""
  MODEL_CFG=""
  PROVIDER_CMD_CFG=""
  TARGET_SHELL_CFG=""
  TIMEOUT_SECONDS_CFG=""
  MAX_RETRIES_CFG=""
  PROMPT_MODE_CFG=""
  UI_MODE_CFG=""
  SHOW_META_CFG=""

  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  PROVIDER_CFG="$(toml_get_string "$config_path" "provider" || true)"
  MODEL_CFG="$(toml_get_string "$config_path" "model" || true)"
  PROVIDER_CMD_CFG="$(toml_get_string "$config_path" "provider_cmd" || true)"
  TARGET_SHELL_CFG="$(toml_get_string "$config_path" "shell" || true)"
  TIMEOUT_SECONDS_CFG="$(toml_get_string "$config_path" "timeout_seconds" || true)"
  MAX_RETRIES_CFG="$(toml_get_string "$config_path" "max_retries" || true)"
  PROMPT_MODE_CFG="$(toml_get_string "$config_path" "prompt_mode" || true)"
  UI_MODE_CFG="$(toml_get_string "$config_path" "ui" || true)"
  SHOW_META_CFG="$(toml_get_string "$config_path" "show_meta" || true)"

  if [[ -n "$profile_name" ]]; then
    local section="profiles.$profile_name"
    local v

    if toml_section_has_key "$config_path" "$section" "provider"; then
      v="$(toml_get_section_string "$config_path" "$section" "provider" || true)"
      PROVIDER_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "model"; then
      v="$(toml_get_section_string "$config_path" "$section" "model" || true)"
      MODEL_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "provider_cmd"; then
      v="$(toml_get_section_string "$config_path" "$section" "provider_cmd" || true)"
      PROVIDER_CMD_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "shell"; then
      v="$(toml_get_section_string "$config_path" "$section" "shell" || true)"
      TARGET_SHELL_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "timeout_seconds"; then
      v="$(toml_get_section_string "$config_path" "$section" "timeout_seconds" || true)"
      TIMEOUT_SECONDS_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "max_retries"; then
      v="$(toml_get_section_string "$config_path" "$section" "max_retries" || true)"
      MAX_RETRIES_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "prompt_mode"; then
      v="$(toml_get_section_string "$config_path" "$section" "prompt_mode" || true)"
      PROMPT_MODE_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "ui"; then
      v="$(toml_get_section_string "$config_path" "$section" "ui" || true)"
      UI_MODE_CFG="$v"
    fi

    if toml_section_has_key "$config_path" "$section" "show_meta"; then
      v="$(toml_get_section_string "$config_path" "$section" "show_meta" || true)"
      SHOW_META_CFG="$v"
    fi
  fi

  return 0
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

run_profile_editor() {
  local config_path="$1"
  local config_dir profile_name section
  local root_provider root_provider_cmd root_shell root_timeout root_retries root_prompt_mode root_ui_mode root_show_meta
  local profile_provider profile_model profile_provider_cmd profile_shell profile_timeout profile_retries profile_prompt_mode profile_ui_mode profile_show_meta
  local new_provider new_model new_provider_cmd new_shell new_timeout new_retries new_prompt_mode new_ui_mode new_show_meta
  local tmp_file

  config_dir="$(dirname "$config_path")"
  mkdir -p "$config_dir"

  if [[ ! -f "$config_path" ]]; then
    cat > "$config_path" <<'CFG'
provider = "codex"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"
CFG
  fi

  load_config_values "$config_path" ""

  root_provider="${PROVIDER_CFG:-codex}"
  root_provider_cmd="${PROVIDER_CMD_CFG:-}"
  root_shell="${TARGET_SHELL_CFG:-zsh}"
  root_timeout="${TIMEOUT_SECONDS_CFG:-30}"
  root_retries="${MAX_RETRIES_CFG:-1}"
  root_prompt_mode="${PROMPT_MODE_CFG:-strict}"
  root_ui_mode="${UI_MODE_CFG:-compact}"
  root_show_meta="$(parse_bool_setting "${SHOW_META_CFG:-0}" "0")"

  echo "Interactive profile editor"
  profile_name="$(prompt_default "Profile name" "custom")"
  [[ -z "$profile_name" ]] && die "Profile name cannot be empty."
  if [[ ! "$profile_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    die "Profile name must match [A-Za-z0-9_-]+"
  fi

  section="profiles.$profile_name"
  profile_provider="$(toml_get_section_string "$config_path" "$section" "provider" || true)"
  profile_model="$(toml_get_section_string "$config_path" "$section" "model" || true)"
  profile_provider_cmd="$(toml_get_section_string "$config_path" "$section" "provider_cmd" || true)"
  profile_shell="$(toml_get_section_string "$config_path" "$section" "shell" || true)"
  profile_timeout="$(toml_get_section_string "$config_path" "$section" "timeout_seconds" || true)"
  profile_retries="$(toml_get_section_string "$config_path" "$section" "max_retries" || true)"
  profile_prompt_mode="$(toml_get_section_string "$config_path" "$section" "prompt_mode" || true)"
  profile_ui_mode="$(toml_get_section_string "$config_path" "$section" "ui" || true)"
  profile_show_meta="$(toml_get_section_string "$config_path" "$section" "show_meta" || true)"

  new_provider="$(prompt_default "provider (codex/gemini/claude/opencode)" "${profile_provider:-$root_provider}")"
  new_model="$(prompt_default "model" "${profile_model:-}")"
  new_provider_cmd="$(prompt_default "provider_cmd" "${profile_provider_cmd:-$root_provider_cmd}")"
  new_shell="$(prompt_default "shell (zsh/bash/fish/powershell)" "${profile_shell:-$root_shell}")"
  new_timeout="$(prompt_default "timeout_seconds" "${profile_timeout:-$root_timeout}")"
  new_retries="$(prompt_default "max_retries" "${profile_retries:-$root_retries}")"
  new_prompt_mode="$(prompt_default "prompt_mode (strict/creative)" "${profile_prompt_mode:-$root_prompt_mode}")"
  new_ui_mode="$(prompt_default "ui (compact/pretty)" "${profile_ui_mode:-$root_ui_mode}")"
  new_show_meta="$(prompt_default "show_meta (0/1)" "${profile_show_meta:-$root_show_meta}")"

  case "$new_provider" in
    codex|gemini|claude|opencode) ;;
    *) die "Invalid provider '$new_provider'. Use codex, gemini, claude, or opencode." ;;
  esac
  case "$new_shell" in
    zsh|bash|fish|powershell) ;;
    *) die "Invalid shell '$new_shell'. Use zsh, bash, fish, or powershell." ;;
  esac
  case "$new_prompt_mode" in
    strict|creative) ;;
    *) die "Invalid prompt_mode '$new_prompt_mode'. Use strict or creative." ;;
  esac
  case "$new_ui_mode" in
    compact|pretty) ;;
    *) die "Invalid ui '$new_ui_mode'. Use compact or pretty." ;;
  esac
  new_show_meta="$(parse_bool_setting "$new_show_meta" "0")"
  is_positive_int "$new_timeout" || die "timeout_seconds must be a positive integer."
  is_positive_int "$new_retries" || die "max_retries must be a positive integer."

  tmp_file="$(mktemp)"
  awk -v target="$section" '
    BEGIN { in_target = 0 }
    /^[[:space:]]*\[/ {
      section = $0
      gsub(/^[[:space:]]*\[/, "", section)
      gsub(/\][[:space:]]*$/, "", section)
      if (section == target) {
        in_target = 1
        next
      }
      if (in_target) {
        in_target = 0
      }
    }
    !in_target { print }
  ' "$config_path" > "$tmp_file"

  {
    cat "$tmp_file"
    printf '\n[profiles.%s]\n' "$profile_name"
    printf 'provider = "%s"\n' "$(toml_escape "$new_provider")"
    printf 'model = "%s"\n' "$(toml_escape "$new_model")"
    printf 'provider_cmd = "%s"\n' "$(toml_escape "$new_provider_cmd")"
    printf 'shell = "%s"\n' "$(toml_escape "$new_shell")"
    printf 'timeout_seconds = "%s"\n' "$(toml_escape "$new_timeout")"
    printf 'max_retries = "%s"\n' "$(toml_escape "$new_retries")"
    printf 'prompt_mode = "%s"\n' "$(toml_escape "$new_prompt_mode")"
    printf 'ui = "%s"\n' "$(toml_escape "$new_ui_mode")"
    printf 'show_meta = "%s"\n' "$(toml_escape "$new_show_meta")"
  } > "$config_path"
  rm -f "$tmp_file"

  echo "Saved profile '$profile_name' to $config_path"
}

run_init() {
  local config_path="$1"
  local force_mode="$2"
  local config_dir

  config_dir="$(dirname "$config_path")"
  mkdir -p "$config_dir"

  if [[ -f "$config_path" && "$force_mode" -ne 1 ]]; then
    die "Config already exists at $config_path. Use 'ai init --force' to overwrite."
  fi

  cat > "$config_path" <<'CFG'
provider = "codex"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"

[profiles.codex]
provider = "codex"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"

[profiles.gemini]
provider = "gemini"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"

[profiles.claude]
provider = "claude"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"

[profiles.opencode]
provider = "opencode"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"
CFG

  echo "Created config at $config_path"
}

is_supported_provider_name() {
  case "$1" in
    codex|gemini|claude|opencode) return 0 ;;
    *) return 1 ;;
  esac
}

is_supported_shell_name() {
  case "$1" in
    zsh|bash|fish|powershell) return 0 ;;
    *) return 1 ;;
  esac
}

is_supported_prompt_mode() {
  case "$1" in
    strict|creative) return 0 ;;
    *) return 1 ;;
  esac
}

is_supported_ui_mode() {
  case "$1" in
    compact|pretty) return 0 ;;
    *) return 1 ;;
  esac
}

validate_config_key_value() {
  local key="$1"
  local value="$2"
  case "$key" in
    provider)
      is_supported_provider_name "$value" || die "Invalid provider '$value'. Use codex, gemini, claude, or opencode."
      ;;
    shell)
      is_supported_shell_name "$value" || die "Invalid shell '$value'. Use zsh, bash, fish, or powershell."
      ;;
    prompt_mode)
      is_supported_prompt_mode "$value" || die "Invalid prompt_mode '$value'. Use strict or creative."
      ;;
    ui)
      is_supported_ui_mode "$value" || die "Invalid ui '$value'. Use compact or pretty."
      ;;
    show_meta)
      parse_bool_setting "$value" "0" >/dev/null
      ;;
    timeout_seconds|max_retries)
      is_positive_int "$value" || die "$key must be a positive integer."
      ;;
    model|provider_cmd)
      ;;
    *)
      die "Unsupported config key '$key'."
      ;;
  esac
}

parse_config_path() {
  local path="$1"
  CONFIG_SCOPE=""
  CONFIG_SECTION=""
  CONFIG_KEY=""

  if [[ "$path" =~ ^profiles\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_]+)$ ]]; then
    CONFIG_SCOPE="section"
    CONFIG_SECTION="profiles.${BASH_REMATCH[1]}"
    CONFIG_KEY="${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$path" =~ ^[A-Za-z0-9_]+$ ]]; then
    CONFIG_SCOPE="root"
    CONFIG_KEY="$path"
    return 0
  fi
  die "Unsupported config path '$path'. Use root keys or profiles.<name>.<key>."
}

config_get_path() {
  local config_path="$1"
  local query_path="$2"
  local value=""

  parse_config_path "$query_path"
  if [[ "$CONFIG_SCOPE" == "root" ]]; then
    toml_root_has_key "$config_path" "$CONFIG_KEY" || die "Config key not found: $query_path"
    value="$(toml_get_string "$config_path" "$CONFIG_KEY" || true)"
  else
    toml_section_has_key "$config_path" "$CONFIG_SECTION" "$CONFIG_KEY" || die "Config key not found: $query_path"
    value="$(toml_get_section_string "$config_path" "$CONFIG_SECTION" "$CONFIG_KEY" || true)"
  fi
  printf '%s\n' "$value"
}

config_set_root_key() {
  local config_path="$1"
  local key="$2"
  local value="$3"
  local escaped_value tmp_file
  escaped_value="$(toml_escape "$value")"
  tmp_file="$(mktemp)"

  awk -v key="$key" -v val="$escaped_value" '
    BEGIN { in_root = 1; updated = 0; inserted = 0 }
    {
      if ($0 ~ /^[[:space:]]*\[/) {
        if (updated == 0 && inserted == 0) {
          print key " = \"" val "\""
          inserted = 1
        }
        in_root = 0
      }
      if (in_root && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" && updated == 0) {
        print key " = \"" val "\""
        updated = 1
        next
      }
      print
    }
    END {
      if (updated == 0 && inserted == 0) {
        print key " = \"" val "\""
      }
    }
  ' "$config_path" > "$tmp_file"
  mv "$tmp_file" "$config_path"
}

config_set_section_key() {
  local config_path="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local escaped_value tmp_file
  escaped_value="$(toml_escape "$value")"
  tmp_file="$(mktemp)"

  awk -v target="$section" -v key="$key" -v val="$escaped_value" '
    BEGIN { in_target = 0; section_found = 0; key_written = 0 }
    /^[[:space:]]*\[/ {
      current = $0
      gsub(/^[[:space:]]*\[/, "", current)
      gsub(/\][[:space:]]*$/, "", current)
      if (in_target && key_written == 0) {
        print key " = \"" val "\""
        key_written = 1
      }
      in_target = (current == target)
      if (in_target) {
        section_found = 1
      }
    }
    {
      if (in_target && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" && key_written == 0) {
        print key " = \"" val "\""
        key_written = 1
        next
      }
      print
    }
    END {
      if (section_found == 0) {
        print ""
        print "[" target "]"
        print key " = \"" val "\""
      } else if (in_target && key_written == 0) {
        print key " = \"" val "\""
      }
    }
  ' "$config_path" > "$tmp_file"
  mv "$tmp_file" "$config_path"
}

config_set_path() {
  local config_path="$1"
  local query_path="$2"
  local value="$3"

  mkdir -p "$(dirname "$config_path")"
  [[ -f "$config_path" ]] || : > "$config_path"

  parse_config_path "$query_path"
  validate_config_key_value "$CONFIG_KEY" "$value"
  if [[ "$CONFIG_KEY" == "show_meta" ]]; then
    value="$(parse_bool_setting "$value" "0")"
  fi

  if [[ "$CONFIG_SCOPE" == "root" ]]; then
    config_set_root_key "$config_path" "$CONFIG_KEY" "$value"
  else
    config_set_section_key "$config_path" "$CONFIG_SECTION" "$CONFIG_KEY" "$value"
  fi
}
