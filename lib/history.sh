#!/usr/bin/env bash

escape_history_field() {
  local value="$1"
  value="${value//$'\t'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s' "$value"
}

append_history() {
  local intent="$1"
  local command="$2"
  local history_file
  history_file="$HISTORY_DIR_DEFAULT/$(date -u +"%Y-%m-%d").log"

  mkdir -p "$HISTORY_DIR_DEFAULT"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$(escape_history_field "$PROVIDER")" \
    "$(escape_history_field "${MODEL:-}")" \
    "$(escape_history_field "$TARGET_SHELL")" \
    "$(escape_history_field "$intent")" \
    "$(escape_history_field "$command")" >> "$history_file"
}

collect_history_entries() {
  local file_list="$1"
  local search_text="${2:-}"
  local output_file="$3"
  local raw_line normalized_line ts provider model shell_name intent command match_target
  local id=0

  : > "$output_file"
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
      [[ -z "$raw_line" ]] && continue
      normalized_line="${raw_line//$'\t'/$'\x1f'}"
      IFS=$'\x1f' read -r ts provider model shell_name intent command <<< "$normalized_line"
      if [[ -z "${ts:-}" || -z "${provider:-}" ]]; then
        continue
      fi
      match_target="$ts $provider ${model:-} ${shell_name:-} ${intent:-} ${command:-}"
      if [[ -n "$search_text" ]] && ! printf '%s\n' "$match_target" | grep -Fqi -- "$search_text"; then
        continue
      fi
      id=$((id + 1))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$ts" "$provider" "${model:-}" "${shell_name:-}" "${intent:-}" "${command:-}" >> "$output_file"
    done < "$file"
  done <<< "$file_list"
}

get_history_command_by_ref() {
  local ref="$1"
  local output_file
  output_file="$(mktemp)"
  local file_list selected_line selected_command

  file_list="$(find "$HISTORY_DIR_DEFAULT" -type f -name '*.log' 2>/dev/null | sort || true)"
  if [[ -z "$file_list" ]]; then
    rm -f "$output_file"
    return 1
  fi

  collect_history_entries "$file_list" "" "$output_file"
  if [[ ! -s "$output_file" ]]; then
    rm -f "$output_file"
    return 1
  fi

  if [[ "$ref" == "latest" ]]; then
    selected_line="$(tail -n 1 "$output_file")"
  elif is_positive_int "$ref"; then
    selected_line="$(awk -F '\t' -v target="$ref" '$1 == target { print; exit }' "$output_file")"
  else
    rm -f "$output_file"
    return 1
  fi

  rm -f "$output_file"
  [[ -z "$selected_line" ]] && return 1
  selected_command="$(printf '%s\n' "$selected_line" | cut -f7-)"
  [[ -z "$selected_command" ]] && return 1
  printf '%s' "$selected_command"
}

show_history() {
  local days="${1:-}"
  local full_mode="${2:-0}"
  local json_mode="${3:-0}"
  local search_text="${4:-}"
  if [[ ! -d "$HISTORY_DIR_DEFAULT" ]]; then
    if [[ "$json_mode" -eq 1 ]]; then
      printf '{"history":[]}\n'
    else
      echo "No history yet."
    fi
    return 0
  fi

  local file_list
  file_list="$(find "$HISTORY_DIR_DEFAULT" -type f -name '*.log' 2>/dev/null | sort || true)"
  if [[ -z "$file_list" ]]; then
    if [[ "$json_mode" -eq 1 ]]; then
      printf '{"history":[]}\n'
    else
      echo "No history yet."
    fi
    return 0
  fi

  if [[ -n "$days" ]]; then
    file_list="$(printf '%s\n' "$file_list" | tail -n "$days")"
  fi

  local entries_file
  entries_file="$(mktemp)"
  if ! collect_history_entries "$file_list" "$search_text" "$entries_file"; then
    rm -f "$entries_file"
    die "Failed to collect history entries."
  fi

  if [[ ! -s "$entries_file" ]]; then
    rm -f "$entries_file"
    if [[ "$json_mode" -eq 1 ]]; then
      printf '{"history":[]}\n'
    else
      echo "No history yet."
    fi
    return 0
  fi

  if [[ "$json_mode" -eq 1 ]]; then
    local raw_line normalized_line id ts provider model shell_name intent command
    local first=1

    printf '{"history":['
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
      [[ -z "$raw_line" ]] && continue
      normalized_line="${raw_line//$'\t'/$'\x1f'}"
      IFS=$'\x1f' read -r id ts provider model shell_name intent command <<< "$normalized_line"
      if [[ "$first" -eq 0 ]]; then
        printf ','
      fi
      first=0
      printf '{"id":%s,"timestamp":"%s","provider":"%s","model":"%s","shell":"%s","intent":"%s","command":"%s"}' \
        "$(json_escape "$id")" \
        "$(json_escape "$ts")" \
        "$(json_escape "$provider")" \
        "$(json_escape "${model:-}")" \
        "$(json_escape "${shell_name:-}")" \
        "$(json_escape "${intent:-}")" \
        "$(json_escape "${command:-}")"
    done < "$entries_file"
    printf ']}\n'
    rm -f "$entries_file"
    return 0
  fi

  local cols ts_w provider_w model_w shell_w intent_w command_w sep_w
  local total_min
  cols=120
  if [[ -t 1 ]] && has_cmd tput; then
    cols="$(tput cols 2>/dev/null || printf '120')"
  fi
  is_positive_int "$cols" || cols=120

  sep_w=3
  ts_w=20
  provider_w=8
  shell_w=10
  if (( cols >= 140 )); then
    model_w=20
    intent_w=34
  elif (( cols >= 120 )); then
    model_w=16
    intent_w=26
  elif (( cols >= 100 )); then
    model_w=12
    intent_w=18
  else
    model_w=10
    intent_w=14
  fi

  total_min=$((4 + ts_w + provider_w + model_w + shell_w + intent_w + (6 * sep_w)))
  command_w=$((cols - total_min))
  if (( command_w < 16 )); then
    command_w=16
  fi

  history_truncate() {
    local value="$1"
    local width="$2"
    if (( width <= 0 )); then
      printf ''
      return 0
    fi
    if (( ${#value} <= width )); then
      printf '%s' "$value"
      return 0
    fi
    if (( width <= 3 )); then
      printf '%.*s' "$width" "$value"
      return 0
    fi
    printf '%s...' "${value:0:$((width - 3))}"
  }

  history_provider_color() {
    local provider="$1"
    case "$provider" in
      codex) printf '%s' "$C_CYAN" ;;
      gemini) printf '%s' "$C_YELLOW" ;;
      claude) printf '%s' "$C_MAGENTA" ;;
      *) printf '%s' "$C_GREEN" ;;
    esac
  }

  if [[ "$full_mode" -eq 1 ]]; then
    printf '%s%s%s\n' "$C_BOLD" "id | timestamp | provider | model | shell | intent | command" "$C_RESET"
  else
    printf '%s%-4s | %-*s | %-*s | %-*s | %-*s | %-*s | %s%s\n' \
      "$C_BOLD" "id" "$ts_w" "timestamp" "$provider_w" "provider" "$model_w" "model" "$shell_w" "shell" "$intent_w" "intent" "command" "$C_RESET"
    printf '%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s\n' \
      4 "$(printf '%*s' 4 '' | tr ' ' '-')" \
      "$ts_w" "$(printf '%*s' "$ts_w" '' | tr ' ' '-')" \
      "$provider_w" "$(printf '%*s' "$provider_w" '' | tr ' ' '-')" \
      "$model_w" "$(printf '%*s' "$model_w" '' | tr ' ' '-')" \
      "$shell_w" "$(printf '%*s' "$shell_w" '' | tr ' ' '-')" \
      "$intent_w" "$(printf '%*s' "$intent_w" '' | tr ' ' '-')" \
      "$command_w" "$(printf '%*s' "$command_w" '' | tr ' ' '-')"
  fi

  local found_any=0
  local id ts provider model shell_name intent command raw_line normalized_line provider_color
  local ts_cell provider_cell model_cell shell_cell intent_cell command_cell
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    [[ -z "$raw_line" ]] && continue
    normalized_line="${raw_line//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r id ts provider model shell_name intent command <<< "$normalized_line"
    found_any=1
    [[ -z "$model" ]] && model="-"
    provider_color="$(history_provider_color "$provider")"
    if [[ "$full_mode" -eq 1 ]]; then
      printf '%s | %s | %s%s%s | %s | %s | %s | %s\n' \
        "$id" "$ts" "$provider_color" "$provider" "$C_RESET" "$model" "$shell_name" "$intent" "$command"
    else
      ts_cell="$(history_truncate "$ts" "$ts_w")"
      provider_cell="$(history_truncate "$provider" "$provider_w")"
      model_cell="$(history_truncate "$model" "$model_w")"
      shell_cell="$(history_truncate "$shell_name" "$shell_w")"
      intent_cell="$(history_truncate "$intent" "$intent_w")"
      command_cell="$(history_truncate "$command" "$command_w")"
      printf '%-4s | %-*s | %s%-*s%s | %-*s | %-*s | %-*s | %s\n' \
        "$id" \
        "$ts_w" "$ts_cell" \
        "$provider_color" "$provider_w" "$provider_cell" "$C_RESET" \
        "$model_w" "$model_cell" \
        "$shell_w" "$shell_cell" \
        "$intent_w" "$intent_cell" \
        "$command_cell"
    fi
  done < "$entries_file"
  rm -f "$entries_file"
  if [[ "$found_any" -eq 0 ]]; then
    echo "No history yet."
    return 0
  fi
}
