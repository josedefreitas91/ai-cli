# ai-cli

`ai-cli` converts natural language into executable terminal commands.

It uses the AI provider CLI the user already has authenticated locally (`codex`, `gemini`, `claude`, `opencode`), without API keys.

## Recommended installation (interactive)

From the project root:

```bash
./install.sh
./install.sh --scope user
./install.sh --scope global
```

One-liner install (from GitHub):

```bash
curl -fsSL https://raw.githubusercontent.com/josedefreitas91/ai-cli/main/install.sh | bash
```

Install from a specific release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/josedefreitas91/ai-cli/main/install.sh | bash -s -- --ref tags/v0.0.1
```

`install.sh` behavior:

- If you run it from the repository root, it installs local source (no download).
- If local source files are not present, it downloads from GitHub releases (latest by default).
- Default scope is user unless you pass `--scope global`.
- Bootstrap repo defaults are in `install.sh`: `GITHUB_OWNER` and `GITHUB_REPO`.

The installer asks for:

- command installation directory
- application home directory
- default provider
- default model (optional)
- custom `provider_cmd` (optional)

Scope defaults:

- `--scope user` installs to `~/.local/bin` by default
- `--scope global` installs to `/usr/local/bin` by default
- user app home defaults to `~/.local/share/ai-cli`
- global app home defaults to `/usr/local/share/ai-cli`

It writes config to:

```bash
~/.config/ai-cli/config.toml
```

If a config file already exists, the installer asks whether to keep it.

## Manual installation

```bash
mkdir -p "$HOME/.local/share/ai-cli/bin" "$HOME/.local/share/ai-cli/lib" "$HOME/.local/share/ai-cli/config"
cp ./bin/ai "$HOME/.local/share/ai-cli/bin/ai"
cp ./lib/*.sh "$HOME/.local/share/ai-cli/lib/"
cp ./config/config.toml.example "$HOME/.local/share/ai-cli/config/config.toml.example"
chmod +x "$HOME/.local/share/ai-cli/bin/ai"
mkdir -p "$HOME/.local/bin"
ln -sfn "$HOME/.local/share/ai-cli/bin/ai" "$HOME/.local/bin/ai"
mkdir -p "$HOME/.config/ai-cli"
cp ./config/config.toml.example "$HOME/.config/ai-cli/config.toml"
```

## Uninstall

Run the interactive uninstaller:

```bash
ai uninstall
```

Alternative (from repository root):

```bash
./uninstall.sh
```

## Configuration

`~/.config/ai-cli/config.toml`:

```toml
provider = "codex"
model = ""
provider_cmd = ""
shell = "zsh"
timeout_seconds = "30"
max_retries = "1"
prompt_mode = "strict"
ui = "compact"
show_meta = "0"

[profiles.fast]
model = "gpt-5.3-codex-spark"
max_retries = "2"
prompt_mode = "creative"
ui = "pretty"
show_meta = "1"
```

- `provider`: `codex`, `gemini`, `claude`, `opencode`
- `model`: optional
- `provider_cmd`: optional override for your provider CLI flags. It must include `{PROMPT}`.
- `shell`: default target shell (`zsh`, `bash`, `fish`, `powershell`)
- `timeout_seconds`: provider timeout
- `max_retries`: retries for transient provider failures
- `prompt_mode`: `strict` (safer, predictable) or `creative` (more concise/powerful command composition)
- `ui`: `compact` (default) or `pretty` (enhanced visual output)
- `show_meta`: `0/1` metadata line visibility (default: `0`)
- `profiles.<name>`: optional profile overrides used with `--profile <name>`

## Usage

```bash
ai "list large files in the current directory"
ai --provider gemini "create a git branch named feature/login"
ai --provider claude --model sonnet "find TODO items in src"
ai --provider opencode "find large files modified in last 2 days"
ai --shell fish "list files sorted by size"
ai --prompt-mode creative "show me the 10 largest files with human-readable sizes"
ai --ui pretty --meta "show me the 10 largest files"
ai --profile fast "find TODO items in src"
ai providers list
ai providers check
ai update
ai update --ref tags/v0.0.1
ai update --scope global
ai config get provider
ai config set profiles.gemini.model ""
ai replay latest
ai --run replay latest
```

Execute the suggested command directly:

```bash
ai --run "list large files in the current directory"
ai --run --confirm "show listening ports"
```

Use explicit dry-run mode:

```bash
ai --dry-run "show listening ports"
ai --no-color --dry-run "show listening ports"
ai --quiet "show listening ports"
```

Show a short explanation:

```bash
ai --explain "find TODO items in src"
```

Get JSON output for automation:

```bash
ai --json --explain "find TODO items in src"
```

Copy command to clipboard:

```bash
ai --copy "show listening ports"
```

Disable automatic clipboard copy:

```bash
ai --no-auto-copy "show listening ports"
```

Tune timeout/retries:

```bash
ai --timeout 20 --max-retries 2 "search TODO comments in src"
```

Show local history:

```bash
ai --history
ai --history --days 7
ai --history --search "git"
ai --history --full
ai --history --json
```

Run diagnostics:

```bash
ai doctor
```

Show help by topic:

```bash
ai help
ai help profile
ai help history
ai help run
ai help init
ai help update
ai help completion
```

Create or edit a profile interactively:

```bash
ai profile
```

Show version:

```bash
ai --version
```

Initialize starter config and provider profiles:

```bash
ai init
ai init --force
```

Generate shell completion:

```bash
ai completion zsh
ai completion bash
ai completion fish
```

Raw model output:

```bash
ai --raw "show listening ports"
```

Note: `--raw` prints provider-native JSON/JSONL output. Some providers emit multiple JSON lines (event streams).

`ai update` checks versions first and skips reinstall when you are already up to date (or already at the requested tag).

## Notes

- Requires at least one published GitHub Release for remote `install.sh` usage (it resolves `latest` release by default).
- Requires the selected provider CLI to be installed and authenticated.
- Uses local CLI authentication; no API key is required.
- You can override the config path with `--config /path/to/config.toml`.
- `ai init` creates `config.toml` with `codex`, `gemini`, `claude`, and `opencode` starter profiles.
- `--run` executes the command. `--confirm` asks before running.
- `--dry-run` is an explicit no-execution mode (same behavior as default).
- `--quiet` minimizes output (no spinner/explanation text).
- Dangerous commands are automatically forced through confirmation.
- History is stored in `~/.config/ai-cli/history/` as daily files (`YYYY-MM-DD.log`).
- `--copy` uses OS-specific clipboard tools:
  - macOS: `pbcopy`
  - Linux: `wl-copy`, `xclip`, or `xsel`
- By default, suggested commands are auto-copied to clipboard (best effort). Use `--no-auto-copy` to disable.


## License

MIT. See `LICENSE`.
