# Install Humanize Skills for Codex

This guide explains how to install Humanize with Codex as the primary agent and Claude as the independent reviewer, including the skill runtime (`$CODEX_HOME/skills`) and native Codex `Stop` hook (`$CODEX_HOME/hooks.json`).

## Quick Install (Recommended)

One-line install from anywhere:

```bash
tmp_dir="$(mktemp -d)" && git clone --depth 1 https://github.com/PolyArch/humanize.git "$tmp_dir/humanize" && "$tmp_dir/humanize/scripts/install-codex-primary-claude-reviewer.sh"
```

From the Humanize repo root:

```bash
./scripts/install-codex-primary-claude-reviewer.sh
```

The one-click installer checks both CLI capabilities and authentication, runs
the existing Humanize installer, and verifies the model configuration, runtime
marker, installed skills, and native Stop hook. It never changes the fixed
agent pairing.

To include a minimal real Claude model call in post-install verification:

```bash
./scripts/install-codex-primary-claude-reviewer.sh --smoke-test
```

The smoke test can consume Claude account/API usage. It is disabled by default.

The compatibility wrapper and unified installer remain available:

```bash
./scripts/install-skills-codex.sh
./scripts/install-skill.sh --target codex
```

This will:
- Sync `humanize`, `humanize-gen-plan`, `humanize-refine-plan`, and `humanize-rlcr` into `${CODEX_HOME:-~/.codex}/skills`
- Copy runtime dependencies into `${CODEX_HOME:-~/.codex}/skills/humanize`
- Install/update native Humanize Stop hooks in `${CODEX_HOME:-~/.codex}/hooks.json`
- Enable the native hooks feature (`hooks`, or legacy `codex_hooks`) in `${CODEX_HOME:-~/.codex}/config.toml` when `codex` is available
- Configure the Codex primary model as `gpt-5.6-sol` with `xhigh` reasoning effort
- Route both summary review and code review through Claude `claude-opus-5` with `max` effort
- Run nested Claude reviews in safe, read-only, non-persistent mode so they cannot recursively trigger Humanize hooks
- Seed `~/.config/humanize/config.json` with a Codex/OpenAI `bitlesson_model` when that key is not already set
- Mark the install as `provider_mode: "codex-only"` when using `--target codex`

Requires Codex CLI `0.114.0` or newer for native hooks, a recent Claude Code
with safe mode and `max` effort support, Python 3, `jq`, and Git. Codex and
Claude must already be authenticated. The installer does not install or log in
either vendor CLI.

## Verify

```bash
ls -la "${CODEX_HOME:-$HOME/.codex}/skills"
```

Expected directories:
- `humanize`
- `humanize-gen-plan`
- `humanize-refine-plan`
- `humanize-rlcr`

Runtime dependencies in `humanize/`:
- `scripts/`
- `hooks/`
- `prompt-template/`
- `templates/`
- `config/`
- `agents/`

Installed files/directories:
- `${CODEX_HOME:-~/.codex}/skills/humanize/SKILL.md`
- `${CODEX_HOME:-~/.codex}/skills/humanize-gen-plan/SKILL.md`
- `${CODEX_HOME:-~/.codex}/skills/humanize-refine-plan/SKILL.md`
- `${CODEX_HOME:-~/.codex}/skills/humanize-rlcr/SKILL.md`
- `${CODEX_HOME:-~/.codex}/skills/humanize/scripts/`
- `${CODEX_HOME:-~/.codex}/skills/humanize/hooks/`
- `${CODEX_HOME:-~/.codex}/skills/humanize/prompt-template/`
- `${CODEX_HOME:-~/.codex}/skills/humanize/templates/`
- `${CODEX_HOME:-~/.codex}/skills/humanize/config/`
- `${CODEX_HOME:-~/.codex}/skills/humanize/agents/`
- `${CODEX_HOME:-~/.codex}/hooks.json`
- `${CODEX_HOME:-~/.codex}/skills/humanize/.codex-primary-claude-reviewer`
- `${XDG_CONFIG_HOME:-~/.config}/humanize/config.json` (created or updated only when Humanize config keys are unset)

Verify native hooks:

```bash
codex features list | rg '^(hooks|codex_hooks)\s'
sed -n '1,220p' "${CODEX_HOME:-$HOME/.codex}/hooks.json"
sed -n '1,20p' "${CODEX_HOME:-$HOME/.codex}/skills/humanize/.codex-primary-claude-reviewer"
sed -n '1,20p' "${CODEX_HOME:-$HOME/.codex}/config.toml"
```

Expected:
- `hooks` (or legacy `codex_hooks`) is `true`
- `hooks.json` contains `loop-codex-stop-hook.sh`
- the runtime marker records `gpt-5.6-sol:xhigh` and `claude-opus-5:max`
- `config.toml` sets `model = "gpt-5.6-sol"` and `model_reasoning_effort = "xhigh"`
- `${XDG_CONFIG_HOME:-~/.config}/humanize/config.json` contains `bitlesson_model` set to a Codex/OpenAI model such as `gpt-5.5`
- for `--target codex`, `${XDG_CONFIG_HOME:-~/.config}/humanize/config.json` also contains `provider_mode: "codex-only"`

## Optional: Install for Both Codex and Kimi

```bash
./scripts/install-skill.sh --target both
```

## Useful Options

```bash
# Preview without writing
./scripts/install-codex-primary-claude-reviewer.sh --dry-run

# Custom Codex home; skills default to /custom/codex/skills
./scripts/install-codex-primary-claude-reviewer.sh \
  --codex-config-dir /custom/codex

# Explicit separate skills directory
./scripts/install-codex-primary-claude-reviewer.sh \
  --codex-config-dir /custom/codex \
  --codex-skills-dir /custom/skills

# Managed/CI environment where authentication is injected externally
./scripts/install-codex-primary-claude-reviewer.sh --skip-auth-check

# Reinstall only the native hooks/config
./scripts/install-codex-hooks.sh
```

## Troubleshooting

If scripts are not found from installed skills:

```bash
ls -la "${CODEX_HOME:-$HOME/.codex}/skills/humanize/scripts"
```

If native exit gating does not trigger:

```bash
codex features enable hooks  # use codex_hooks on older Codex releases
sed -n '1,220p' "${CODEX_HOME:-$HOME/.codex}/hooks.json"
```
