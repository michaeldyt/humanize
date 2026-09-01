#!/usr/bin/env bash
#
# Tests for Codex-native hook installation and merge behavior.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

INSTALL_SCRIPT="$PROJECT_ROOT/scripts/install-skill.sh"

echo "=========================================="
echo "Codex Hook Install Tests"
echo "=========================================="
echo ""

if [[ ! -x "$INSTALL_SCRIPT" ]]; then
    echo "FATAL: install-skill.sh not found at $INSTALL_SCRIPT" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "FATAL: python3 is required for this test" >&2
    exit 1
fi

setup_test_dir

FAKE_BIN="$TEST_DIR/bin"
CODEX_HOME_DIR="$TEST_DIR/codex-home"
HOOKS_FILE="$CODEX_HOME_DIR/hooks.json"
FEATURE_LOG="$TEST_DIR/codex-features.log"
XDG_CONFIG_HOME_DIR="$TEST_DIR/xdg-config"
HUMANIZE_USER_CONFIG="$XDG_CONFIG_HOME_DIR/humanize/config.json"
COMMAND_BIN_DIR="$TEST_DIR/command-bin"
mkdir -p "$FAKE_BIN" "$CODEX_HOME_DIR" "$COMMAND_BIN_DIR"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "features" && "${2:-}" == "list" ]]; then
    feature="${TEST_CODEX_HOOKS_FEATURE:-codex_hooks}"
    printf '%-36s stable             false\n' "$feature"
    exit 0
fi

if [[ "${1:-}" == "features" && "${2:-}" == "enable" && "${3:-}" == "${TEST_CODEX_HOOKS_FEATURE:-codex_hooks}" ]]; then
    printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-}" >> "${TEST_CODEX_FEATURE_LOG:?}"
    printf 'FEATURE=%s\n' "${3:-}" >> "${TEST_CODEX_FEATURE_LOG:?}"
    mkdir -p "${CODEX_HOME:?}"
    : > "${CODEX_HOME}/.codex-hooks-enabled"
    exit 0
fi

if [[ "${1:-}" == "exec" ]]; then
    cat <<'OUT'
LESSON_IDS: NONE
RATIONALE: No matching lessons found (fake codex exec).
OUT
    exit 0
fi

echo "unexpected fake codex invocation: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/codex"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/claude"

cat > "$HOOKS_FILE" <<'EOF'
{
  "description": "Existing hooks",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/custom/session-start.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/old/skills/humanize/hooks/loop-codex-stop-hook.sh",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "/custom/keep-me.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF

cat > "$CODEX_HOME_DIR/config.toml" <<'EOF'
# Existing Codex settings must be preserved.
model = "gpt-5.2"
model_reasoning_effort = "low"

[features]
shell_snapshot = true
EOF

PATH="$FAKE_BIN:$PATH" TEST_CODEX_FEATURE_LOG="$FEATURE_LOG" XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$CODEX_HOME_DIR" \
    --codex-skills-dir "$CODEX_HOME_DIR/skills" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install.log" 2>&1

if [[ -f "$CODEX_HOME_DIR/skills/humanize/SKILL.md" ]]; then
    pass "Codex install syncs Humanize skill bundle"
else
    fail "Codex install syncs Humanize skill bundle" "skills/humanize/SKILL.md exists" "missing"
fi

if [[ -f "$CODEX_HOME_DIR/skills/humanize-rlcr/SKILL.md" ]]; then
    pass "Codex install keeps humanize-rlcr entrypoint skill"
else
    fail "Codex install keeps humanize-rlcr entrypoint skill" "skills/humanize-rlcr/SKILL.md exists" "missing"
fi

if [[ -f "$HOOKS_FILE" ]]; then
    pass "Codex install writes hooks.json"
else
    fail "Codex install writes hooks.json" "$HOOKS_FILE exists" "missing"
fi

if [[ -f "$CODEX_HOME_DIR/.codex-hooks-enabled" ]]; then
    pass "Codex install enables codex_hooks feature"
else
    fail "Codex install enables codex_hooks feature" ".codex-hooks-enabled marker exists" "missing"
fi

if [[ -f "$CODEX_HOME_DIR/skills/humanize/.codex-primary-claude-reviewer" ]] \
    && grep -q '^codex-primary=gpt-5.6-sol:xhigh$' "$CODEX_HOME_DIR/skills/humanize/.codex-primary-claude-reviewer" \
    && grep -q '^reviewer=claude-opus-5:max$' "$CODEX_HOME_DIR/skills/humanize/.codex-primary-claude-reviewer"; then
    pass "Codex install marks the fixed Codex-to-Claude runtime"
else
    fail "Codex install marks the fixed Codex-to-Claude runtime" \
        "fixed reviewer marker" \
        "$(cat "$CODEX_HOME_DIR/skills/humanize/.codex-primary-claude-reviewer" 2>/dev/null || echo missing)"
fi

if grep -q '^model = "gpt-5.6-sol"$' "$CODEX_HOME_DIR/config.toml" \
    && grep -q '^model_reasoning_effort = "xhigh"$' "$CODEX_HOME_DIR/config.toml" \
    && grep -q '^shell_snapshot = true$' "$CODEX_HOME_DIR/config.toml"; then
    pass "Codex install configures the fixed primary model and effort"
else
    fail "Codex install configures the fixed primary model and effort" \
        "gpt-5.6-sol:xhigh in config.toml" \
        "$(cat "$CODEX_HOME_DIR/config.toml" 2>/dev/null || echo missing)"
fi

if [[ -f "$HUMANIZE_USER_CONFIG" ]]; then
    pass "Codex install writes Humanize user config"
else
    fail "Codex install writes Humanize user config" "$HUMANIZE_USER_CONFIG exists" "missing"
fi

if [[ -x "$COMMAND_BIN_DIR/bitlesson-selector" ]]; then
    pass "Codex install writes a PATH-ready bitlesson-selector shim"
else
    fail "Codex install writes a PATH-ready bitlesson-selector shim" "$COMMAND_BIN_DIR/bitlesson-selector exists" "missing"
fi

if [[ "$(jq -r '.bitlesson_model // empty' "$HUMANIZE_USER_CONFIG")" == "gpt-5.5" ]]; then
    pass "Codex install seeds bitlesson_model with a Codex/OpenAI model"
else
    fail "Codex install seeds bitlesson_model with a Codex/OpenAI model" \
        "gpt-5.5" "$(jq -c '.' "$HUMANIZE_USER_CONFIG" 2>/dev/null || echo MISSING)"
fi

if [[ "$(jq -r '.provider_mode // empty' "$HUMANIZE_USER_CONFIG")" == "codex-only" ]]; then
    pass "Codex install marks Humanize user config as codex-only"
else
    fail "Codex install marks Humanize user config as codex-only" \
        "codex-only" "$(jq -c '.' "$HUMANIZE_USER_CONFIG" 2>/dev/null || echo MISSING)"
fi

runtime_root="$CODEX_HOME_DIR/skills/humanize"
PY_OUTPUT="$(
    python3 - "$HOOKS_FILE" "$runtime_root" <<'PY'
import json
import pathlib
import sys

hooks_file = pathlib.Path(sys.argv[1])
runtime_root = sys.argv[2]
data = json.loads(hooks_file.read_text(encoding="utf-8"))

commands = []
for group in data["hooks"]["Stop"]:
    for hook in group.get("hooks", []):
        command = hook.get("command")
        if isinstance(command, str):
            commands.append(command)

expected = {
    f"{runtime_root}/hooks/loop-codex-stop-hook.sh",
}

print("FOUND=" + ("1" if expected.issubset(set(commands)) else "0"))
print("KEEP=" + ("1" if "/custom/keep-me.sh" in commands else "0"))
print("OLD=" + ("1" if any("/tmp/old/skills/humanize/hooks/" in cmd for cmd in commands) else "0"))
print("SESSION=" + ("1" if data["hooks"]["SessionStart"][0]["hooks"][0]["command"] == "/custom/session-start.sh" else "0"))
print("COUNT=" + str(sum(1 for cmd in commands if "/humanize/hooks/" in cmd)))
PY
)"

if grep -q '^FOUND=1$' <<<"$PY_OUTPUT"; then
    pass "Codex install adds managed Humanize Stop hook commands"
else
    fail "Codex install adds managed Humanize Stop hook commands" "FOUND=1" "$PY_OUTPUT"
fi

if grep -q '^KEEP=1$' <<<"$PY_OUTPUT"; then
    pass "Codex install preserves unrelated Stop hooks"
else
    fail "Codex install preserves unrelated Stop hooks" "KEEP=1" "$PY_OUTPUT"
fi

if grep -q '^OLD=0$' <<<"$PY_OUTPUT"; then
    pass "Codex install removes stale Humanize hook commands"
else
    fail "Codex install removes stale Humanize hook commands" "OLD=0" "$PY_OUTPUT"
fi

if grep -q '^SESSION=1$' <<<"$PY_OUTPUT"; then
    pass "Codex install preserves SessionStart hooks"
else
    fail "Codex install preserves SessionStart hooks" "SESSION=1" "$PY_OUTPUT"
fi

if grep -q '^COUNT=1$' <<<"$PY_OUTPUT"; then
    pass "Codex install writes exactly one managed Humanize Stop hook"
else
    fail "Codex install writes exactly one managed Humanize Stop hook" "COUNT=1" "$PY_OUTPUT"
fi

mkdir -p "$TEST_DIR/project"
cat > "$TEST_DIR/project/bitlesson.md" <<'EOF'
# BitLesson Knowledge Base
## Entries
<!-- placeholder -->
EOF

shim_output="$(
    CLAUDE_PROJECT_DIR="$TEST_DIR/project" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    PATH="$COMMAND_BIN_DIR:$FAKE_BIN:$PATH" \
    "$COMMAND_BIN_DIR/bitlesson-selector" \
    --task "Verify the shim dispatches into the installed runtime" \
    --paths "README.md" \
    --bitlesson-file "$TEST_DIR/project/bitlesson.md"
)"

if grep -q '^LESSON_IDS: NONE$' <<<"$shim_output"; then
    pass "bitlesson-selector shim dispatches into installed runtime"
else
    fail "bitlesson-selector shim dispatches into installed runtime" "LESSON_IDS: NONE" "$shim_output"
fi

PATH="$FAKE_BIN:$PATH" TEST_CODEX_FEATURE_LOG="$FEATURE_LOG" XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$CODEX_HOME_DIR" \
    --codex-skills-dir "$CODEX_HOME_DIR/skills" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install-2.log" 2>&1

PY_OUTPUT_2="$(
    python3 - "$HOOKS_FILE" <<'PY'
import json
import pathlib
import sys

hooks_file = pathlib.Path(sys.argv[1])
data = json.loads(hooks_file.read_text(encoding="utf-8"))

commands = []
for group in data["hooks"]["Stop"]:
    for hook in group.get("hooks", []):
        command = hook.get("command")
        if isinstance(command, str):
            commands.append(command)

print(sum(1 for cmd in commands if "/humanize/hooks/" in cmd))
PY
)"

if [[ "$PY_OUTPUT_2" == "1" ]]; then
    pass "Codex install is idempotent for managed hook commands"
else
    fail "Codex install is idempotent for managed hook commands" "1" "$PY_OUTPUT_2"
fi

if [[ "$(grep -c '^model = "gpt-5.6-sol"$' "$CODEX_HOME_DIR/config.toml")" == "1" ]] \
    && [[ "$(grep -c '^model_reasoning_effort = "xhigh"$' "$CODEX_HOME_DIR/config.toml")" == "1" ]]; then
    pass "Codex primary model configuration is idempotent"
else
    fail "Codex primary model configuration is idempotent" \
        "one model and effort assignment" \
        "$(cat "$CODEX_HOME_DIR/config.toml")"
fi

if [[ "$(grep -c '^CODEX_HOME=' "$FEATURE_LOG")" == "2" ]]; then
    pass "Codex feature enable runs on each Codex install/update"
else
    fail "Codex feature enable runs on each Codex install/update" "2 log entries" "$(cat "$FEATURE_LOG")"
fi

MODERN_HOME="$TEST_DIR/codex-home-modern"
MODERN_FEATURE_LOG="$TEST_DIR/codex-features-modern.log"
PATH="$FAKE_BIN:$PATH" TEST_CODEX_HOOKS_FEATURE="hooks" \
    TEST_CODEX_FEATURE_LOG="$MODERN_FEATURE_LOG" XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$MODERN_HOME" \
    --codex-skills-dir "$MODERN_HOME/skills" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install-modern.log" 2>&1

if grep -q '^FEATURE=hooks$' "$MODERN_FEATURE_LOG" && [[ -f "$MODERN_HOME/hooks.json" ]]; then
    pass "Codex install supports the stable hooks feature name"
else
    fail "Codex install supports the stable hooks feature name" \
        "FEATURE=hooks and hooks.json" \
        "$(cat "$MODERN_FEATURE_LOG" 2>/dev/null || true)"
fi

NO_CLAUDE_BIN="$TEST_DIR/bin-no-claude"
NO_CLAUDE_HOME="$TEST_DIR/codex-home-no-claude"
mkdir -p "$NO_CLAUDE_BIN" "$NO_CLAUDE_HOME"
cat > "$NO_CLAUDE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "features" && "${2:-}" == "list" ]]; then
    echo "hooks                              stable             true"
    exit 0
fi
if [[ "${1:-}" == "features" && "${2:-}" == "enable" ]]; then
    exit 0
fi
exit 1
EOF
chmod +x "$NO_CLAUDE_BIN/codex"

set +e
PATH="$NO_CLAUDE_BIN:/usr/local/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$NO_CLAUDE_HOME" \
    --codex-skills-dir "$NO_CLAUDE_HOME/skills" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install-no-claude.log" 2>&1
NO_CLAUDE_EXIT=$?
set -e

if [[ "$NO_CLAUDE_EXIT" -ne 0 ]] && grep -q 'Claude Code CLI is required' "$TEST_DIR/install-no-claude.log"; then
    pass "Codex install requires the fixed Claude reviewer dependency"
else
    fail "Codex install requires the fixed Claude reviewer dependency" \
        "non-zero exit with Claude dependency error" \
        "exit=$NO_CLAUDE_EXIT output=$(cat "$TEST_DIR/install-no-claude.log")"
fi

UNSUPPORTED_BIN="$TEST_DIR/bin-unsupported"
UNSUPPORTED_HOME="$TEST_DIR/codex-home-unsupported"
mkdir -p "$UNSUPPORTED_BIN" "$UNSUPPORTED_HOME"

cat > "$UNSUPPORTED_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "features" && "${2:-}" == "list" ]]; then
    cat <<'LIST'
apply_patch_freeform             under development  false
LIST
    exit 0
fi

echo "unexpected fake codex invocation: $*" >&2
exit 1
EOF
chmod +x "$UNSUPPORTED_BIN/codex"

set +e
PATH="$UNSUPPORTED_BIN:$PATH" XDG_CONFIG_HOME="$XDG_CONFIG_HOME_DIR" \
    "$INSTALL_SCRIPT" \
    --target codex \
    --codex-config-dir "$UNSUPPORTED_HOME" \
    --codex-skills-dir "$UNSUPPORTED_HOME/skills" \
    --command-bin-dir "$COMMAND_BIN_DIR" \
    > "$TEST_DIR/install-unsupported.log" 2>&1
UNSUPPORTED_EXIT=$?
set -e

if [[ "$UNSUPPORTED_EXIT" -ne 0 ]]; then
    pass "Codex install rejects builds without native hooks support"
else
    fail "Codex install rejects builds without native hooks support" "non-zero exit" "exit 0"
fi

if grep -q "native hooks" "$TEST_DIR/install-unsupported.log"; then
    pass "Unsupported Codex failure explains missing codex_hooks feature"
else
    fail "Unsupported Codex failure explains missing codex_hooks feature" \
        "error mentioning native hooks" \
        "$(cat "$TEST_DIR/install-unsupported.log")"
fi

print_test_summary "Codex Hook Install Tests"
