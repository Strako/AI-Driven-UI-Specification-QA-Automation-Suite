#!/bin/bash
# PIPELINE HOOK — PRE-TOOL-USE ON TEST-EXECUTION DISPATCH
# Fires before qa-coordinator dispatches a sub-agent via the Agent tool.
#
# Gates the test-execution dispatch specifically: once dispatched, test-execution
# runs to completion in one shot and cannot pause mid-run to ask the user anything
# — only qa-coordinator (the live, turn-by-turn agent) can do that. So this hook is
# the earliest point where "the test-execution stage is about to start" can be
# observed and, if needed, blocked so qa-coordinator can ask a question first.
#
# Two independent gates run in order:
#
#   Gate 1 — Test data confirmation. Blocks until the user has explicitly said
#   test-data.md is filled in. State is written GENERATION_COMPLETE by
#   pipeline-on-tests-generated.sh right after test-cases.md is produced, and
#   advanced to TEST_DATA_READY by pipeline-on-user-prompt.sh once the user replies.
#   This gate is intentionally NOT bypassed by "auto" permission mode alone — it
#   only bypasses when the dispatch prompt carries `AUTO_TEST_DATA: true`, which
#   qa-coordinator only sets when the user's *initial* request explicitly asked
#   for automatic test data generation (in which case test-generation already
#   filled test-data.md itself, using vars.md plus inferred values, instead of
#   leaving it blank). Absent that explicit request, this gate blocks and asks
#   the user to fill test-data.md regardless of permission_mode — running the
#   suite unattended against unfilled data is exactly what this gate exists to
#   prevent.
#
#   Gate 2 — Execution roughness level (1 Critical / 2 Critical+Mid / 3 All).
#   This gate IS bypassed by "auto" permission mode (defaults to 3/All) — mode
#   only affects Gate 2, never Gate 1.

PROJECT="${PWD}"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" \
  2>/dev/null || echo "")

[[ "$TOOL_NAME" != "Agent" && "$TOOL_NAME" != "Task" ]] && exit 0

PROMPT_TEXT=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('prompt', ti.get('task', ti.get('description',''))))" \
  2>/dev/null || echo "")

[[ -z "$PROMPT_TEXT" ]] && exit 0

# Only gate the test-execution dispatch — its prompt always includes both of these.
# test-generation's dispatch prompt has neither, so it passes through untouched.
echo "$PROMPT_TEXT" | grep -q "TEST_CASES_FILE:" || exit 0
echo "$PROMPT_TEXT" | grep -q "TEST_DATA_FILE:" || exit 0

TEST_CASES_LINE=$(echo "$PROMPT_TEXT" | grep "TEST_CASES_FILE:" | head -1)
TEST_CASES_PATH=$(echo "$TEST_CASES_LINE" | sed -E 's/.*TEST_CASES_FILE:[[:space:]]*//' | xargs)
MODULE_DIR=$(dirname "$TEST_CASES_PATH")
MODULE=$(basename "$MODULE_DIR")

# ── Gate 1: test data confirmation ─────────────────────────────────────────
# Bypassed only by an explicit AUTO_TEST_DATA: true marker (set by qa-coordinator
# only when the user's initial request explicitly asked for automatic test data
# generation) — never by permission_mode alone.
if ! echo "$PROMPT_TEXT" | grep -qE "AUTO_TEST_DATA:[[:space:]]*true"; then
  # Only blocks when the pipeline state for THIS module is still GENERATION_COMPLETE
  # (i.e. the user has not yet replied to confirm test-data.md is filled in). A
  # missing state file, or state belonging to a different module, is not treated
  # as "unconfirmed" — that covers Execute Only invocations against pre-existing
  # test-cases.md/test-data.md from an earlier session.
  if [[ -f "$STATE_FILE" ]]; then
    CURRENT_STATE=$(sed -n '1p' "$STATE_FILE")
    STATE_MODULE=$(sed -n '2p' "$STATE_FILE")

    if [[ "$CURRENT_STATE" == "GENERATION_COMPLETE" && "$STATE_MODULE" == "$MODULE" ]]; then
      cat <<MSG >&2
Test data has not been confirmed yet for module "$MODULE". This gate is not
affected by Claude Code's permission mode — it blocks regardless of auto mode
unless the user's initial request explicitly asked for automatic test data
generation. Do NOT retry this dispatch yet — first stop and tell the user:

  Stage 1 complete — test cases and test-data.md were generated for "$MODULE".
  Fill in test-data.md, then reply here (e.g. "done") when ready.

Wait for their reply in the conversation. The UserPromptSubmit hook recognizes
a confirmation reply (done/ready/filled/proceed/go ahead/continue/next/execute/run)
and will tell you to retry this dispatch once it sees one.
MSG
      exit 2
    fi
  fi
fi

# ── Gate 2: execution roughness level ──────────────────────────────────────
# Already resolved — either the user pre-specified it, or this is a retry after
# qa-coordinator already asked and got an answer. Let it through.
echo "$PROMPT_TEXT" | grep -qE "EXECUTION_LEVEL:[[:space:]]*[123]" && exit 0

PERMISSION_MODE=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('permission_mode',''))" \
  2>/dev/null || echo "")

# Auto mode: nobody is necessarily watching to answer a question — skip this
# gate and default to running everything. test-execution itself defaults
# EXECUTION_LEVEL to 3 (All) when the field is absent from its input. Unlike
# Gate 1 above, this bypass is intentional and unchanged — only Gate 1 (test
# data) is exempted from the auto-mode bypass.
[[ "$PERMISSION_MODE" == "auto" ]] && exit 0

mkdir -p "$(dirname "$STATE_FILE")"
printf "AWAITING_EXECUTION_LEVEL\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"

cat <<MSG >&2
Execution roughness level not specified and the session is not in Claude Code's
"auto" permission mode. Do NOT retry this dispatch yet — first ask the user directly:

  Before executing, how thorough should this run be?
  1 — Critical only
  2 — Critical + Mid
  3 — All

If you have the SEVERITY_BREAKDOWN counts from test-generation's completion
block for this module, show them next to each option (e.g. "1 — Critical only (12 tests)").

Wait for their reply in the conversation, then retry dispatching test-execution
with an EXECUTION_LEVEL: {1|2|3} line added to the prompt.
MSG

exit 2
