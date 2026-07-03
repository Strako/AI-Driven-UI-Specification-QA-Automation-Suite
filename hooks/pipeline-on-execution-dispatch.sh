#!/bin/bash
# PIPELINE HOOK — PRE-TOOL-USE ON TEST-EXECUTION DISPATCH
# Fires before qa-coordinator dispatches a sub-agent via the Agent tool.
#
# Gates the test-execution dispatch specifically: once dispatched, test-execution
# runs to completion in one shot and cannot pause mid-run to ask the user anything
# — only qa-coordinator (the live, turn-by-turn agent) can do that, the same way it
# already pauses for the user to fill test-data.md. So this hook is the earliest
# point where "the test-execution stage is about to start" can be observed and,
# if needed, blocked so qa-coordinator can ask a question first.
#
# If the session is not in Claude Code's "auto" permission mode and no
# EXECUTION_LEVEL was already resolved, blocks the dispatch (exit 2) and tells
# qa-coordinator to ask the user for a roughness level (1 Critical / 2 Critical+Mid
# / 3 All) before retrying. In "auto" mode, or once a level is already present in
# the dispatch prompt, the dispatch is allowed through unchanged.

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

# Already resolved — either the user pre-specified it, or this is a retry after
# qa-coordinator already asked and got an answer. Let it through.
echo "$PROMPT_TEXT" | grep -qE "EXECUTION_LEVEL:[[:space:]]*[123]" && exit 0

PERMISSION_MODE=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('permission_mode',''))" \
  2>/dev/null || echo "")

# Auto mode: nobody is necessarily watching to answer a question — default to
# running everything. test-execution itself defaults EXECUTION_LEVEL to 3 (All)
# when the field is absent from its input.
[[ "$PERMISSION_MODE" == "auto" ]] && exit 0

TEST_CASES_LINE=$(echo "$PROMPT_TEXT" | grep "TEST_CASES_FILE:" | head -1)
TEST_CASES_PATH=$(echo "$TEST_CASES_LINE" | sed -E 's/.*TEST_CASES_FILE:[[:space:]]*//' | xargs)
MODULE_DIR=$(dirname "$TEST_CASES_PATH")
MODULE=$(basename "$MODULE_DIR")

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
