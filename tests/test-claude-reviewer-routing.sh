#!/usr/bin/env bash
# Verify Codex-native installs route both RLCR review phases through Claude.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=========================================="
echo "Claude Reviewer Routing Tests"
echo "=========================================="
echo ""

setup_test_dir
export XDG_CACHE_HOME="$TEST_DIR/.cache"
export XDG_CONFIG_HOME="$TEST_DIR/config"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

STOP_HOOK="$PROJECT_ROOT/hooks/loop-codex-stop-hook.sh"
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${TEST_CLAUDE_ARGS:?}"
cat > "${TEST_CLAUDE_PROMPT:?}"
printf '%s\n' "${TEST_CLAUDE_OUTPUT:?}"
EOF
chmod +x "$FAKE_BIN/claude"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: > "${TEST_CODEX_CALLED:?}"
echo "codex reviewer must not run in codex-only mode" >&2
exit 97
EOF
chmod +x "$FAKE_BIN/codex"

setup_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir"
    git -C "$repo_dir" init -q
    git -C "$repo_dir" config user.email test@example.com
    git -C "$repo_dir" config user.name "Test User"
    git -C "$repo_dir" config commit.gpgsign false

    mkdir -p "$repo_dir/plans" "$repo_dir/.humanize"
    cat > "$repo_dir/.gitignore" <<'EOF'
.humanize/rlcr/
.cache/
EOF
cat > "$repo_dir/plans/test-plan.md" <<'EOF'
# Test Plan
## Goal
Exercise the fixed Claude reviewer route.
## Acceptance Criteria
- Claude performs summary review.
- Claude performs code review.
EOF
    echo "initial" > "$repo_dir/app.txt"
    git -C "$repo_dir" add .gitignore plans/test-plan.md app.txt
    git -C "$repo_dir" commit -q -m initial
}

setup_loop() {
    local repo_dir="$1"
    local review_started="$2"
    local loop_dir="$repo_dir/.humanize/rlcr/2026-08-31_12-00-00"
    local branch base_commit
    branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)"
    base_commit="$(git -C "$repo_dir" rev-parse HEAD)"

    mkdir -p "$loop_dir"
    cat > "$loop_dir/state.md" <<EOF
---
current_round: 1
max_iterations: 42
plan_file: plans/test-plan.md
plan_tracked: false
start_branch: $branch
base_branch: $branch
base_commit: $base_commit
push_every_round: false
codex_model: gpt-5.6-sol
codex_effort: xhigh
codex_timeout: 120
review_started: $review_started
full_review_round: 5
ask_codex_question: false
agent_teams: false
privacy_mode: true
bitlesson_required: false
started_at: 2026-08-31T12:00:00Z
---
EOF
    cp "$repo_dir/plans/test-plan.md" "$loop_dir/plan.md"
    cat > "$loop_dir/goal-tracker.md" <<'EOF'
# Goal Tracker
## IMMUTABLE SECTION
### Ultimate Goal
Exercise reviewer routing.
### Acceptance Criteria
- AC-1: Claude is the reviewer.

## MUTABLE SECTION
### Active Tasks
- Verify routing.
EOF
    cat > "$loop_dir/round-1-summary.md" <<'EOF'
# Round Summary
Implemented the requested work and ran tests.
EOF
    if [[ "$review_started" == "true" ]]; then
        echo "build_finish_round=1" > "$loop_dir/.review-phase-started"
    fi
}

run_hook() {
    local repo_dir="$1"
    local mode="$2"
    local reviewer_output="$3"

    TEST_CLAUDE_ARGS="$TEST_DIR/$mode.args" \
    TEST_CLAUDE_PROMPT="$TEST_DIR/$mode.prompt" \
    TEST_CLAUDE_OUTPUT="$reviewer_output" \
    TEST_CODEX_CALLED="$TEST_DIR/$mode.codex-called" \
    HUMANIZE_CODEX_PRIMARY=true \
    PATH="$FAKE_BIN:$PATH" \
    CLAUDE_PROJECT_DIR="$repo_dir" \
        bash "$STOP_HOOK" <<< '{}' > "$TEST_DIR/$mode.out" 2> "$TEST_DIR/$mode.err"
}

assert_claude_contract() {
    local mode="$1"
    local args_file="$TEST_DIR/$mode.args"
    local args=""
    args="$(tr '\n' ' ' < "$args_file" 2>/dev/null || true)"

    if [[ "$args" == *"--safe-mode"* ]] \
        && [[ "$args" == *"--permission-mode plan"* ]] \
        && [[ "$args" == *"--model claude-opus-5"* ]] \
        && [[ "$args" == *"--effort max"* ]] \
        && [[ "$args" == *"--no-session-persistence"* ]] \
        && [[ "$args" == *"--output-format text"* ]] \
        && [[ "$args" == *"-p"* ]]; then
        pass "$mode review uses fixed Claude model, max effort, and recursion-safe read-only mode"
    else
        fail "$mode review uses fixed Claude model, max effort, and recursion-safe read-only mode" \
            "required Claude arguments" "$args; stderr=$(cat "$TEST_DIR/$mode.err" 2>/dev/null || true); stdout=$(cat "$TEST_DIR/$mode.out" 2>/dev/null || true)"
    fi

    if [[ ! -e "$TEST_DIR/$mode.codex-called" ]]; then
        pass "$mode review does not invoke nested Codex"
    else
        fail "$mode review does not invoke nested Codex" "Codex not called" "Codex called"
    fi
}

IMPL_REPO="$TEST_DIR/impl-repo"
setup_repo "$IMPL_REPO"
setup_loop "$IMPL_REPO" false
run_hook "$IMPL_REPO" implementation $'## Mainline Gaps\nContinue verification.\nMainline Progress Verdict: ADVANCED'
assert_claude_contract implementation

if grep -q "independent reviewer for work implemented by a Codex agent" "$TEST_DIR/implementation.prompt"; then
    pass "implementation review uses the Codex-to-Claude prompt"
else
    fail "implementation review uses the Codex-to-Claude prompt" \
        "Codex-to-Claude reviewer instructions" "$(head -20 "$TEST_DIR/implementation.prompt" 2>/dev/null || true)"
fi

IMPL_NEXT_PROMPT="$(find "$IMPL_REPO/.humanize/rlcr" -name round-2-prompt.md -type f -print -quit 2>/dev/null || true)"
if [[ -n "$IMPL_NEXT_PROMPT" ]] \
    && grep -q 'Codex executes directly' "$IMPL_NEXT_PROMPT" \
    && grep -q 'Claude is review-only' "$IMPL_NEXT_PROMPT" \
    && ! grep -q 'Claude executes directly' "$IMPL_NEXT_PROMPT" \
    && ! grep -q '/humanize:ask-codex' "$IMPL_NEXT_PROMPT"; then
    pass "Codex-native follow-up prompts keep Claude review-only"
else
    fail "Codex-native follow-up prompts keep Claude review-only" \
        "Codex owns tasks and Claude only reviews" \
        "$(cat "$IMPL_NEXT_PROMPT" 2>/dev/null || echo missing)"
fi

REVIEW_REPO="$TEST_DIR/review-repo"
setup_repo "$REVIEW_REPO"
setup_loop "$REVIEW_REPO" true
run_hook "$REVIEW_REPO" code-review "NO_FINDINGS"
assert_claude_contract code-review

if grep -q "Effective review base" "$TEST_DIR/code-review.prompt" \
    && grep -q "NO_FINDINGS" "$TEST_DIR/code-review.prompt"; then
    pass "code review supplies Claude with the diff baseline and output contract"
else
    fail "code review supplies Claude with the diff baseline and output contract" \
        "review baseline and NO_FINDINGS contract" "$(head -30 "$TEST_DIR/code-review.prompt" 2>/dev/null || true)"
fi

SETUP_REPO="$TEST_DIR/setup-repo"
setup_repo "$SETUP_REPO"
set +e
SETUP_OUTPUT=$(cd "$SETUP_REPO" && \
    HUMANIZE_CODEX_PRIMARY=true PATH="$FAKE_BIN:$PATH" \
    bash "$PROJECT_ROOT/scripts/setup-rlcr-loop.sh" \
        --track-plan-file \
        --base-branch master \
        --skip-quiz \
        --codex-model gpt-5.2:low \
        plans/test-plan.md 2>&1)
SETUP_EXIT=$?
set -e
SETUP_STATE="$(find "$SETUP_REPO/.humanize/rlcr" -name state.md -type f -print -quit 2>/dev/null || true)"
SETUP_PROMPT="${SETUP_STATE%/state.md}/round-0-prompt.md"
SETUP_GOAL_TRACKER="${SETUP_STATE%/state.md}/goal-tracker.md"

if [[ "$SETUP_EXIT" -eq 0 ]] \
    && grep -q '^codex_model: gpt-5.6-sol$' "$SETUP_STATE" \
    && grep -q '^codex_effort: xhigh$' "$SETUP_STATE" \
    && grep -q 'Primary Agent: Codex (gpt-5.6-sol:xhigh)' <<< "$SETUP_OUTPUT" \
    && grep -q 'Review Agent: Claude (claude-opus-5:max)' <<< "$SETUP_OUTPUT"; then
    pass "Codex-native setup fixes the requested primary and reviewer models"
else
    fail "Codex-native setup fixes the requested primary and reviewer models" \
        "fixed models in state and setup output" \
        "exit=$SETUP_EXIT state=$(cat "$SETUP_STATE" 2>/dev/null || true) output=$SETUP_OUTPUT"
fi

if grep -q 'Tags `coding` and `analyze` are both executed by the Codex primary agent' "$SETUP_PROMPT" \
    && grep -q 'Claude is review-only' "$SETUP_PROMPT" \
    && ! grep -q 'Claude executes the task directly' "$SETUP_PROMPT" \
    && grep -q '| codex | mainline task only |' "$SETUP_GOAL_TRACKER"; then
    pass "Codex-native initial prompt assigns all implementation work to Codex"
else
    fail "Codex-native initial prompt assigns all implementation work to Codex" \
        "Codex task ownership and Claude review-only role" \
        "prompt=$(sed -n '/Task Tag Routing/,/^$/p' "$SETUP_PROMPT" 2>/dev/null || true) tracker=$(grep 'mainline task only' "$SETUP_GOAL_TRACKER" 2>/dev/null || true)"
fi

if grep -q -- '--codex-model is ignored' <<< "$SETUP_OUTPUT"; then
    pass "Codex-native setup rejects model drift by overriding legacy reviewer flags"
else
    fail "Codex-native setup rejects model drift by overriding legacy reviewer flags" \
        "override warning" "$SETUP_OUTPUT"
fi

print_test_summary "Claude Reviewer Routing Tests"
