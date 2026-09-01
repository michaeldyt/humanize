#!/usr/bin/env bash
#
# Tests for the fixed Codex-primary/Claude-reviewer one-click installer.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

INSTALLER="$PROJECT_ROOT/scripts/install-codex-primary-claude-reviewer.sh"

echo "=========================================="
echo "One-click Codex + Claude Install Tests"
echo "=========================================="
echo ""

if [[ ! -x "$INSTALLER" ]]; then
    echo "FATAL: installer is missing or not executable: $INSTALLER" >&2
    exit 1
fi

setup_test_dir

FAKE_BIN="$TEST_DIR/bin"
CODEX_LOG="$TEST_DIR/codex.log"
CLAUDE_LOG="$TEST_DIR/claude.log"
XDG_CONFIG_HOME_DIR="$TEST_DIR/xdg"
mkdir -p "$FAKE_BIN" "$XDG_CONFIG_HOME_DIR"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'CODEX_HOME=%s ARGS=' "${CODEX_HOME:-}" >> "${TEST_CODEX_LOG:?}"
printf '%q ' "$@" >> "${TEST_CODEX_LOG:?}"
printf '\n' >> "${TEST_CODEX_LOG:?}"

if [[ "${1:-}" == "--version" ]]; then
    echo "codex-cli 0.151.0"
    exit 0
fi

if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
    [[ "${TEST_CODEX_AUTH_FAIL:-false}" != "true" ]]
    exit $?
fi

if [[ "${1:-}" == "features" && "${2:-}" == "list" ]]; then
    enabled=false
    codex_home="${CODEX_HOME:-}"
    if [[ -n "$codex_home" && -f "$codex_home/.hooks-enabled" ]]; then
        enabled=true
    fi
    printf '%-36s stable             %s\n' hooks "$enabled"
    exit 0
fi

if [[ "${1:-}" == "features" && "${2:-}" == "enable" && "${3:-}" == "hooks" ]]; then
    mkdir -p "${CODEX_HOME:?}"
    : > "${CODEX_HOME}/.hooks-enabled"
    exit 0
fi

echo "unexpected fake codex invocation: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/codex"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'ARGS=' >> "${TEST_CLAUDE_LOG:?}"
printf '%q ' "$@" >> "${TEST_CLAUDE_LOG:?}"
printf '\n' >> "${TEST_CLAUDE_LOG:?}"

if [[ "${1:-}" == "--help" ]]; then
    cat <<'HELP'
--safe-mode
--no-session-persistence
--effort <level> (low, medium, high, xhigh, max)
HELP
    exit 0
fi

if [[ "${1:-}" == "--version" ]]; then
    echo "2.1.251 (Claude Code)"
    exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    [[ "${TEST_CLAUDE_AUTH_FAIL:-false}" != "true" ]]
    [[ "${TEST_CLAUDE_AUTH_FAIL:-false}" != "true" ]] && echo '{"loggedIn":true}'
    exit $?
fi

if [[ " $* " == *" -p "* ]]; then
    cat >/dev/null
    echo "HUMANIZE_CLAUDE_REVIEWER_OK"
    exit 0
fi

echo "unexpected fake claude invocation: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/claude"

run_installer() {
    local codex_home="$1"
    local command_bin="$2"
    shift 2

    (
        export PATH="$FAKE_BIN:$PATH"
        export TEST_CODEX_LOG="$CODEX_LOG"
        export TEST_CLAUDE_LOG="$CLAUDE_LOG"
        export XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR"
        "$INSTALLER" \
        --codex-config-dir "$codex_home" \
        --command-bin-dir "$command_bin" \
        "$@"
    )
}

HELP_OUTPUT="$($INSTALLER --help)"
if grep -q 'gpt-5.6-sol:xhigh' <<<"$HELP_OUTPUT" \
    && grep -q 'claude-opus-5:max' <<<"$HELP_OUTPUT" \
    && grep -q -- '--smoke-test' <<<"$HELP_OUTPUT"; then
    pass "installer help documents the fixed pairing and optional smoke test"
else
    fail "installer help documents the fixed pairing and optional smoke test" \
        "fixed models and --smoke-test" "$HELP_OUTPUT"
fi

CODEX_HOME_1="$TEST_DIR/codex-home-1"
COMMAND_BIN_1="$TEST_DIR/command-bin-1"
set +e
INSTALL_OUTPUT="$(run_installer "$CODEX_HOME_1" "$COMMAND_BIN_1" 2>&1)"
INSTALL_EXIT=$?
set -e

if [[ "$INSTALL_EXIT" -eq 0 ]] && grep -q 'Installation verified successfully' <<<"$INSTALL_OUTPUT"; then
    pass "one-click installer completes installation and verification"
else
    fail "one-click installer completes installation and verification" \
        "exit 0 and success message" \
        "exit=$INSTALL_EXIT output=$INSTALL_OUTPUT codex-log=$(cat "$CODEX_LOG" 2>/dev/null || true)"
fi

if [[ -f "$CODEX_HOME_1/skills/humanize/.codex-primary-claude-reviewer" ]] \
    && grep -q '^codex-primary=gpt-5.6-sol:xhigh$' "$CODEX_HOME_1/skills/humanize/.codex-primary-claude-reviewer" \
    && grep -q '^reviewer=claude-opus-5:max$' "$CODEX_HOME_1/skills/humanize/.codex-primary-claude-reviewer"; then
    pass "one-click installer writes the fixed agent-routing marker"
else
    fail "one-click installer writes the fixed agent-routing marker" \
        "fixed pairing marker" \
        "$(cat "$CODEX_HOME_1/skills/humanize/.codex-primary-claude-reviewer" 2>/dev/null || echo missing)"
fi

if [[ -f "$CODEX_HOME_1/config.toml" ]] \
    && grep -q '^model = "gpt-5.6-sol"$' "$CODEX_HOME_1/config.toml" \
    && grep -q '^model_reasoning_effort = "xhigh"$' "$CODEX_HOME_1/config.toml" \
    && [[ -f "$CODEX_HOME_1/hooks.json" ]]; then
    pass "one-click installer configures the Codex primary and native hook"
else
    fail "one-click installer configures the Codex primary and native hook" \
        "model, effort, and hooks.json" \
        "$(cat "$CODEX_HOME_1/config.toml" 2>/dev/null || echo missing)"
fi

if grep -q 'ARGS=login status' "$CODEX_LOG" \
    && grep -q 'ARGS=auth status --json' "$CLAUDE_LOG"; then
    pass "one-click installer checks both CLI authentications"
else
    fail "one-click installer checks both CLI authentications" \
        "Codex and Claude auth status calls" \
        "codex=$(cat "$CODEX_LOG") claude=$(cat "$CLAUDE_LOG")"
fi

CODEX_HOME_2="$TEST_DIR/codex-home-2"
COMMAND_BIN_2="$TEST_DIR/command-bin-2"
SMOKE_OUTPUT="$(run_installer "$CODEX_HOME_2" "$COMMAND_BIN_2" --smoke-test --smoke-timeout 30)"

if grep -q 'Claude reviewer smoke test passed' <<<"$SMOKE_OUTPUT" \
    && grep -q -- '--model claude-opus-5' "$CLAUDE_LOG" \
    && grep -q -- '--effort max' "$CLAUDE_LOG" \
    && grep -q -- '--safe-mode' "$CLAUDE_LOG" \
    && grep -q -- '--permission-mode plan' "$CLAUDE_LOG"; then
    pass "optional smoke test calls the fixed Claude reviewer in safe plan mode"
else
    fail "optional smoke test calls the fixed Claude reviewer in safe plan mode" \
        "fixed Claude invocation" \
        "output=$SMOKE_OUTPUT log=$(cat "$CLAUDE_LOG")"
fi

CODEX_HOME_AUTH_FAIL="$TEST_DIR/codex-home-auth-fail"
set +e
AUTH_FAIL_OUTPUT="$(
    TEST_CLAUDE_AUTH_FAIL=true \
        run_installer "$CODEX_HOME_AUTH_FAIL" "$TEST_DIR/command-bin-auth-fail" 2>&1
)"
AUTH_FAIL_EXIT=$?
set -e

if [[ "$AUTH_FAIL_EXIT" -ne 0 ]] \
    && grep -q 'Claude Code is not authenticated' <<<"$AUTH_FAIL_OUTPUT" \
    && [[ ! -e "$CODEX_HOME_AUTH_FAIL/hooks.json" ]]; then
    pass "authentication failure stops before installation writes"
else
    fail "authentication failure stops before installation writes" \
        "non-zero before hooks.json" \
        "exit=$AUTH_FAIL_EXIT output=$AUTH_FAIL_OUTPUT"
fi

CODEX_HOME_SKIP_AUTH="$TEST_DIR/codex-home-skip-auth"
set +e
SKIP_AUTH_OUTPUT="$(
    TEST_CODEX_AUTH_FAIL=true TEST_CLAUDE_AUTH_FAIL=true \
        run_installer "$CODEX_HOME_SKIP_AUTH" "$TEST_DIR/command-bin-skip-auth" --skip-auth-check 2>&1
)"
SKIP_AUTH_EXIT=$?
set -e

if [[ "$SKIP_AUTH_EXIT" -eq 0 ]] \
    && grep -q 'authentication checks skipped by request' <<<"$SKIP_AUTH_OUTPUT" \
    && [[ -f "$CODEX_HOME_SKIP_AUTH/hooks.json" ]]; then
    pass "--skip-auth-check supports non-interactive managed environments"
else
    fail "--skip-auth-check supports non-interactive managed environments" \
        "successful install without auth probes" \
        "exit=$SKIP_AUTH_EXIT output=$SKIP_AUTH_OUTPUT"
fi

DRY_HOME="$TEST_DIR/codex-home-dry"
DRY_OUTPUT="$(run_installer "$DRY_HOME" "$TEST_DIR/command-bin-dry" --dry-run)"
if grep -q 'dry run complete' <<<"$DRY_OUTPUT" \
    && [[ ! -e "$DRY_HOME/hooks.json" ]]; then
    pass "--dry-run previews without writing installation files"
else
    fail "--dry-run previews without writing installation files" \
        "dry-run message and no hooks.json" \
        "output=$DRY_OUTPUT"
fi

print_test_summary "One-click Codex + Claude Install Tests"
