#!/bin/bash
# PIPELINE HOOK — STATE: GENERATION_COMPLETE
# Fires after every Write tool call.
#
# test-generation (per its skill) writes test-cases.md first (Step 4), then
# test-data.md (Step 5) in the same run. The GENERATION_COMPLETE state
# transition below is deliberately keyed off the test-data.md write — the
# *second* of the two — not test-cases.md. This guarantees
# pipeline-on-test-data-edit-gate.sh's PreToolUse check on that same
# test-data.md write never sees GENERATION_COMPLETE yet (this is a
# PostToolUse hook, so it only sets the state *after* the write already
# completed) — meaning test-generation's own Step 5 write can never be
# blocked by that gate.
#
# qa-coordinator reports Stage 1 completion and attempts the Stage 2 dispatch right
# away; pipeline-on-execution-dispatch.sh reads this GENERATION_COMPLETE state to
# decide whether that dispatch must actually block for test-data confirmation
# (skipped outright when the session is in Claude Code's "auto" permission mode).
#
# Also creates the module's evidences/ subfolder here, deterministically, rather
# than relying on test-execution to create it — that agent has no Bash/mkdir tool,
# only Read/Write/Edit/Glob/Grep/MCP, and Playwright's screenshot call may not
# create missing intermediate directories on its own. This is tied to the
# test-cases.md write specifically (independent of the state transition above,
# which fires later) so evidences/ is guaranteed to exist by the time the first
# screenshot is captured.

PROJECT="${PWD}"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != "$PROJECT/Platform/"* ]] && exit 0

MODULE_DIR=$(dirname "$FILE")
MODULE=$(basename "$MODULE_DIR")
BASENAME=$(basename "$FILE")

# Match: Platform/**/test-cases.md — create evidences/ up front.
if [[ "$BASENAME" == "test-cases.md" ]]; then
  mkdir -p "$MODULE_DIR/evidences"
fi

# Match: Platform/**/test-data.md — the second and final artifact test-generation
# writes, so this is the right point to flip pipeline state to GENERATION_COMPLETE.
# Only fires when a sibling test-cases.md exists, confirming this really is a
# generation run and not an unrelated write to a file that happens to be named
# test-data.md. qa-coordinator handles the pause message and the
# pipeline-on-user-prompt hook handles dispatch of test-execution on "done".
if [[ "$BASENAME" == "test-data.md" ]] && [[ -f "$MODULE_DIR/test-cases.md" ]]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  printf "GENERATION_COMPLETE\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"
fi

exit 0
