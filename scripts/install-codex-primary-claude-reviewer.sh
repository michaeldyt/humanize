#!/usr/bin/env bash
#
# One-click Humanize installer for the fixed agent pairing:
#   primary:  Codex gpt-5.6-sol:xhigh
#   reviewer: Claude claude-opus-5:max
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_SKILLS_DIR="$CODEX_CONFIG_DIR/skills"
CODEX_SKILLS_DIR_EXPLICIT="false"
COMMAND_BIN_DIR="${HUMANIZE_COMMAND_BIN_DIR:-${HOME}/.local/bin}"
DRY_RUN="false"
SKIP_AUTH_CHECK="false"
RUN_SMOKE_TEST="false"
SMOKE_TIMEOUT=600

readonly CODEX_PRIMARY_MODEL="gpt-5.6-sol"
readonly CODEX_PRIMARY_EFFORT="xhigh"
readonly CLAUDE_REVIEW_MODEL="claude-opus-5"
readonly CLAUDE_REVIEW_EFFORT="max"

usage() {
    cat <<'EOF'
Install Humanize with Codex as the primary agent and Claude as the reviewer.

Usage:
  scripts/install-codex-primary-claude-reviewer.sh [options]

Fixed agent pairing:
  Codex primary:   gpt-5.6-sol:xhigh
  Claude reviewer: claude-opus-5:max

Options:
  --repo-root PATH        Humanize source root (default: auto-detect)
  --codex-config-dir PATH Codex config directory (default: ${CODEX_HOME:-~/.codex})
  --codex-skills-dir PATH Codex skills directory (default: <codex-config-dir>/skills)
  --command-bin-dir PATH  Helper command directory (default: ~/.local/bin)
  --skip-auth-check       Skip `codex login status` and `claude auth status`
  --smoke-test            Make one minimal Claude API call after installation
  --smoke-timeout N       Smoke-test timeout in seconds (default: 600)
  --dry-run               Show the underlying installation actions without writing
  -h, --help              Show this help message

The script installs Humanize only. It does not install the Codex or Claude CLIs
and does not perform interactive login.
EOF
}

log() {
    printf '[codex-primary-claude-reviewer] %s\n' "$*"
}

die() {
    printf '[codex-primary-claude-reviewer] Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local command_name="$1"
    local install_hint="$2"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        die "$command_name is required. $install_hint"
    fi
}

check_cli_capabilities() {
    local claude_help

    require_command codex "Install and authenticate a hooks-capable Codex CLI first."
    require_command claude "Install and authenticate Claude Code first."
    require_command python3 "Install Python 3 and rerun this script."
    require_command jq "Install jq; the Humanize Stop hook requires it at runtime."
    require_command git "Install Git; RLCR reviews compare committed branch changes."

    claude_help="$(claude --help 2>&1)" || die "Could not inspect Claude Code capabilities."
    grep -q -- '--safe-mode' <<<"$claude_help" || \
        die "Installed Claude Code does not support --safe-mode; upgrade Claude Code."
    grep -q -- '--no-session-persistence' <<<"$claude_help" || \
        die "Installed Claude Code does not support --no-session-persistence; upgrade Claude Code."
    grep -q -- '--effort' <<<"$claude_help" || \
        die "Installed Claude Code does not support --effort; upgrade Claude Code."
    grep -q -- 'xhigh, max' <<<"$claude_help" || \
        die "Installed Claude Code does not advertise max effort; upgrade Claude Code."
}

check_authentication() {
    local codex_auth_output
    local claude_auth_output

    [[ "$SKIP_AUTH_CHECK" == "false" ]] || {
        log "authentication checks skipped by request"
        return 0
    }

    if ! codex_auth_output="$(CODEX_HOME="$CODEX_CONFIG_DIR" codex login status 2>&1)"; then
        die "Codex is not authenticated for $CODEX_CONFIG_DIR. Run: CODEX_HOME=\"$CODEX_CONFIG_DIR\" codex login"
    fi

    if ! claude_auth_output="$(claude auth status --json 2>&1)"; then
        die "Claude Code is not authenticated. Run: claude auth login"
    fi

    log "Codex and Claude authentication checks passed"
}

verify_hooks_feature() {
    local features

    features="$(CODEX_HOME="$CODEX_CONFIG_DIR" codex features list 2>/dev/null)" || \
        die "Could not verify Codex native hooks after installation."

    if ! awk '
        ($1 == "hooks" || $1 == "codex_hooks") && $NF == "true" { found = 1 }
        END { exit(found ? 0 : 1) }
    ' <<<"$features"; then
        die "Codex native hooks are not enabled in $CODEX_CONFIG_DIR/config.toml."
    fi
}

verify_installed_files() {
    local runtime_root="$CODEX_SKILLS_DIR/humanize"
    local config_file="$CODEX_CONFIG_DIR/config.toml"
    local hooks_file="$CODEX_CONFIG_DIR/hooks.json"
    local marker_file="$runtime_root/.codex-primary-claude-reviewer"

    python3 - \
        "$config_file" \
        "$hooks_file" \
        "$marker_file" \
        "$runtime_root" \
        "$CODEX_PRIMARY_MODEL" \
        "$CODEX_PRIMARY_EFFORT" \
        "$CLAUDE_REVIEW_MODEL" \
        "$CLAUDE_REVIEW_EFFORT" <<'PY'
import json
import pathlib
import re
import shlex
import sys

(
    config_path,
    hooks_path,
    marker_path,
    runtime_path,
    codex_model,
    codex_effort,
    claude_model,
    claude_effort,
) = sys.argv[1:]

config_file = pathlib.Path(config_path)
hooks_file = pathlib.Path(hooks_path)
marker_file = pathlib.Path(marker_path)
runtime_root = pathlib.Path(runtime_path)


def fail(message: str) -> None:
    print(f"installation verification failed: {message}", file=sys.stderr)
    raise SystemExit(1)


required_files = [
    runtime_root / "SKILL.md",
    runtime_root.parent / "humanize-rlcr" / "SKILL.md",
    runtime_root / "hooks" / "loop-codex-stop-hook.sh",
    runtime_root / "hooks" / "lib" / "loop-common.sh",
]
for required_file in required_files:
    if not required_file.is_file():
        fail(f"missing {required_file}")

if not config_file.is_file():
    fail(f"missing {config_file}")

config_lines = config_file.read_text(encoding="utf-8").splitlines()
preamble = []
for line in config_lines:
    if re.match(r"^\s*\[", line):
        break
    preamble.append(line)


def read_top_level_string(key):
    pattern = re.compile(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"\s*$')
    values = [match.group(1) for line in preamble if (match := pattern.match(line))]
    if len(values) != 1:
        fail(f"expected exactly one top-level {key} assignment in {config_file}")
    return values[0]


if read_top_level_string("model") != codex_model:
    fail(f"Codex model is not {codex_model}")
if read_top_level_string("model_reasoning_effort") != codex_effort:
    fail(f"Codex reasoning effort is not {codex_effort}")

if not marker_file.is_file():
    fail(f"missing fixed-routing marker {marker_file}")
marker_lines = set(marker_file.read_text(encoding="utf-8").splitlines())
expected_marker_lines = {
    f"codex-primary={codex_model}:{codex_effort}",
    f"reviewer={claude_model}:{claude_effort}",
}
if marker_lines != expected_marker_lines:
    fail(f"unexpected fixed-routing marker contents in {marker_file}")

if not hooks_file.is_file():
    fail(f"missing {hooks_file}")
try:
    hooks_data = json.loads(hooks_file.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    fail(f"invalid hooks config {hooks_file}: {exc}")

expected_hook = str(runtime_root / "hooks" / "loop-codex-stop-hook.sh")
managed_hook_count = 0
for group in hooks_data.get("hooks", {}).get("Stop", []):
    if not isinstance(group, dict):
        continue
    for hook in group.get("hooks", []):
        if not isinstance(hook, dict) or not isinstance(hook.get("command"), str):
            continue
        try:
            command = shlex.split(hook["command"])
        except ValueError:
            continue
        if command and command[0] == expected_hook:
            managed_hook_count += 1

if managed_hook_count != 1:
    fail(f"expected one managed Stop hook for {expected_hook}, found {managed_hook_count}")

common_text = (runtime_root / "hooks" / "lib" / "loop-common.sh").read_text(encoding="utf-8")
if f'CLAUDE_REVIEW_MODEL="{claude_model}"' not in common_text:
    fail(f"installed runtime does not fix Claude model to {claude_model}")
if f'CLAUDE_REVIEW_EFFORT="{claude_effort}"' not in common_text:
    fail(f"installed runtime does not fix Claude effort to {claude_effort}")
PY

    [[ -x "$COMMAND_BIN_DIR/bitlesson-selector" ]] || \
        die "bitlesson-selector shim is missing or not executable: $COMMAND_BIN_DIR/bitlesson-selector"
}

run_claude_smoke_test() {
    local smoke_dir
    local smoke_output
    local smoke_exit=0

    smoke_dir="$(mktemp -d)"

    printf '%s\n' \
        'This is an installation smoke test. Reply with exactly HUMANIZE_CLAUDE_REVIEWER_OK and nothing else.' \
        | run_with_timeout "$SMOKE_TIMEOUT" \
            claude \
            --safe-mode \
            --permission-mode plan \
            --model "$CLAUDE_REVIEW_MODEL" \
            --effort "$CLAUDE_REVIEW_EFFORT" \
            --no-session-persistence \
            --output-format text \
            --tools "" \
            -p \
            > "$smoke_dir/stdout" 2> "$smoke_dir/stderr" || smoke_exit=$?

    if [[ "$smoke_exit" -ne 0 ]]; then
        tail -30 "$smoke_dir/stderr" >&2 || true
        rm -rf "$smoke_dir"
        die "Claude reviewer smoke test failed with exit code $smoke_exit."
    fi

    smoke_output="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$smoke_dir/stdout")"
    if [[ "$smoke_output" != "HUMANIZE_CLAUDE_REVIEWER_OK" ]]; then
        rm -rf "$smoke_dir"
        die "Claude reviewer smoke test returned unexpected output: $smoke_output"
    fi

    rm -rf "$smoke_dir"
    log "Claude reviewer smoke test passed"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            [[ -n "${2:-}" ]] || die "--repo-root requires a path"
            REPO_ROOT="$2"
            shift 2
            ;;
        --codex-config-dir)
            [[ -n "${2:-}" ]] || die "--codex-config-dir requires a path"
            CODEX_CONFIG_DIR="$2"
            shift 2
            ;;
        --codex-skills-dir)
            [[ -n "${2:-}" ]] || die "--codex-skills-dir requires a path"
            CODEX_SKILLS_DIR="$2"
            CODEX_SKILLS_DIR_EXPLICIT="true"
            shift 2
            ;;
        --command-bin-dir)
            [[ -n "${2:-}" ]] || die "--command-bin-dir requires a path"
            COMMAND_BIN_DIR="$2"
            shift 2
            ;;
        --skip-auth-check)
            SKIP_AUTH_CHECK="true"
            shift
            ;;
        --smoke-test)
            RUN_SMOKE_TEST="true"
            shift
            ;;
        --smoke-timeout)
            [[ -n "${2:-}" ]] || die "--smoke-timeout requires a number"
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "--smoke-timeout must be a positive integer"
            SMOKE_TIMEOUT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

if [[ "$CODEX_SKILLS_DIR_EXPLICIT" == "false" ]]; then
    CODEX_SKILLS_DIR="$CODEX_CONFIG_DIR/skills"
fi

[[ -x "$REPO_ROOT/scripts/install-skill.sh" ]] || \
    die "Humanize installer not found: $REPO_ROOT/scripts/install-skill.sh"

# shellcheck source=scripts/portable-timeout.sh
source "$REPO_ROOT/scripts/portable-timeout.sh"

check_cli_capabilities
check_authentication

log "Codex CLI: $(codex --version 2>/dev/null || echo unknown)"
log "Claude CLI: $(claude --version 2>/dev/null || echo unknown)"
log "installing fixed pairing: $CODEX_PRIMARY_MODEL:$CODEX_PRIMARY_EFFORT -> $CLAUDE_REVIEW_MODEL:$CLAUDE_REVIEW_EFFORT"

install_args=(
    --target codex
    --repo-root "$REPO_ROOT"
    --codex-config-dir "$CODEX_CONFIG_DIR"
    --codex-skills-dir "$CODEX_SKILLS_DIR"
    --command-bin-dir "$COMMAND_BIN_DIR"
)
[[ "$DRY_RUN" == "true" ]] && install_args+=(--dry-run)

"$REPO_ROOT/scripts/install-skill.sh" "${install_args[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
    log "dry run complete; no post-install verification was performed"
    exit 0
fi

verify_hooks_feature
verify_installed_files

if [[ "$RUN_SMOKE_TEST" == "true" ]]; then
    run_claude_smoke_test
fi

cat <<EOF

Installation verified successfully.
  Primary agent:   Codex $CODEX_PRIMARY_MODEL:$CODEX_PRIMARY_EFFORT
  Review agent:    Claude $CLAUDE_REVIEW_MODEL:$CLAUDE_REVIEW_EFFORT
  Codex config:    $CODEX_CONFIG_DIR/config.toml
  Humanize skills: $CODEX_SKILLS_DIR
  Native hooks:    $CODEX_CONFIG_DIR/hooks.json

Restart any running Codex session so the fixed primary model is reloaded.
EOF
