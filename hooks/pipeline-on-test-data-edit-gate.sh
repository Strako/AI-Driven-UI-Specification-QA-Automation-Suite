#!/bin/bash
# PIPELINE HOOK — PRE-TOOL-USE ON TEST-DATA.MD EDIT/WRITE
# Fires before every Write and Edit tool call. Blocks direct modification of a
# module's test-data.md while pipeline state for that module is
# GENERATION_COMPLETE (i.e. the user has not yet confirmed test-data.md is
# filled in by replying exactly "done" — see pipeline-on-user-prompt.sh).
#
# This closes a gap in pipeline-on-execution-dispatch.sh's Gate 1: that hook
# only gates the Agent-tool dispatch of test-execution, not a direct Read+Edit
# (or Write) of test-data.md itself. Nothing previously stopped an assistant —
# in particular, the top-level orchestrator that regains control once a
# backgrounded qa-coordinator dispatch returns with the "paused, waiting for
# test data" message as its final output — from rationalizing "auto mode is
# active" and filling test-data.md in itself, bypassing the confirmation the
# gate exists to enforce. Like Gate 1, this hook is NOT bypassed by Claude
# Code's permission mode: it is a hard block regardless of auto mode, since
# the entire point is to prevent exactly the "let me fill this in myself in
# auto mode" reasoning that caused the original incident.
#
# The only way to populate test-data.md automatically is to request automatic
# test data generation in the initial message, which routes through
# test-generation's own AUTO_FILL_TEST_DATA path (see
# skills/test-generation:process/SKILL.md Step 5) — that write happens before
# this module's state ever becomes GENERATION_COMPLETE (see
# pipeline-on-tests-generated.sh, which keys the transition off the
# test-data.md write itself), so it is never blocked by this gate.
#
# That same explicit-upfront-request case is also the one documented exception
# where further edits to test-data.md ARE allowed afterward (user-guide.md Step
# 3.5: "nothing stops you from editing it further before test execution actually
# starts"). pipeline-on-spec-dispatch.sh records a per-module
# .auto-test-data-{MODULE} marker when it sees AUTO_FILL_TEST_DATA: true on the
# test-generation dispatch — this gate skips its block when that marker exists,
# since the user already explicitly opted out of manual confirmation for this
# module, unlike the default (blank-template, no upfront request) case this gate
# exists to protect.

PROJECT="${PWD}"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" \
  2>/dev/null || echo "")

[[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]] && exit 0

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != "$PROJECT/Platform/"* ]] && exit 0
[[ "$(basename "$FILE")" != "test-data.md" ]] && exit 0

[[ ! -f "$STATE_FILE" ]] && exit 0

MODULE_DIR=$(dirname "$FILE")
MODULE=$(basename "$MODULE_DIR")

# This module's test data was auto-filled by an explicit upfront request —
# further edits are documented, sanctioned behavior (see user-guide.md Step 3.5),
# not the unconfirmed-manual-fill case this gate protects. Let it through.
[[ -f "$PROJECT/.claude/.auto-test-data-${MODULE}" ]] && exit 0

CURRENT_STATE=$(sed -n '1p' "$STATE_FILE")
STATE_MODULE=$(sed -n '2p' "$STATE_FILE")

if [[ "$CURRENT_STATE" == "GENERATION_COMPLETE" && "$STATE_MODULE" == "$MODULE" ]]; then
  cat <<MSG >&2
Test data has not been confirmed yet for module "$MODULE" — do NOT edit or
overwrite test-data.md yourself. This gate is not affected by Claude Code's
permission mode: it blocks regardless of auto mode, including a rationale
like "auto mode is active, so I'll fill this in myself." The user must open
test-data.md and fill it in themselves, then reply with exactly the word
"done" (nothing else, no other words before or after it).

If automatic test data generation was intended, it can only be requested in
the *initial* message to qa-coordinator (before test-generation ever runs) —
that routes through test-generation's own AUTO_FILL_TEST_DATA path instead of
a direct edit here. It cannot be retroactively applied once generation has
already completed and this pause has begun.

Stop now and tell the user:

  Test data has not been confirmed yet for module "$MODULE". Open
  test-data.md, fill in every \${field-name} placeholder yourself, then reply
  with exactly the word "done" once ready.

Wait for their reply in the conversation.
MSG
  exit 2
fi

exit 0
