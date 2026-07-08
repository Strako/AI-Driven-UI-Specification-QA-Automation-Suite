#!/bin/bash
# PIPELINE HOOK — USER PROMPT SUBMIT
# Fires on every user message.
# Routes pipeline transitions based on current state:
#
#   WIZARD_OFFER_PENDING      + yes    → WIZARD_REQUESTED      → qa-coordinator dispatches spec-wizard-improve
#   WIZARD_OFFER_PENDING      + no     → WIZARD_OFFER_ANSWERED → retry qa-coordinator's test-generation dispatch
#   QA_PIPELINE_OFFER_PENDING + yes    → QA_PIPELINE_CONFIRMED → retry qa-coordinator dispatch (standalone path only)
#   QA_PIPELINE_OFFER_PENDING + no     → (stop)                → tell agent to print "spec complete" and stop
#   GENERATION_COMPLETE       + done   → TEST_DATA_READY       → dispatch test-execution
#   AWAITING_EXECUTION_LEVEL  + 1/2/3  → TEST_DATA_READY       → retry test-execution dispatch with EXECUTION_LEVEL set
#
# WIZARD_OFFER_PENDING is set by pipeline-on-spec-dispatch.sh when it gates
# qa-coordinator's OWN Stage 1 (test-generation) dispatch, right after a Stage 0
# bootstrap in the same run. QA_PIPELINE_OFFER_PENDING is set by the same hook
# but only ever arises from a standalone spec-wizard-improve/spec-wizard-pipeline
# invocation (qa-coordinator's default flow has no "run the pipeline?" question
# at all). Both block (exit 2) only outside Claude Code's "auto" permission mode
# — in auto mode they let the corresponding dispatch through immediately and
# neither state/branch ever comes into play. (The docs/ enrichment gate,
# pipeline-on-spec-write-gate.sh, is fully automatic and never involves a user
# reply at all, so it has no corresponding branch here.)
#
# GENERATION_COMPLETE's "done" branch, unlike every other gate here, resolves
# regardless of permission_mode — the test-data confirmation wait is not
# skipped by auto mode alone, only by an explicit auto-fill request made in
# the initial prompt (see pipeline-on-execution-dispatch.sh and
# qa-coordinator's AUTO_TEST_DATA handling).

PROJECT="${PWD}"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

[[ ! -f "$STATE_FILE" ]] && exit 0

CURRENT_STATE=$(sed -n '1p' "$STATE_FILE")
MODULE=$(sed -n '2p' "$STATE_FILE")
PATH_LINE=$(sed -n '3p' "$STATE_FILE")

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('prompt','').lower())" \
  2>/dev/null || echo "")

[[ -z "$PROMPT" ]] && exit 0

YES_RE="(^yes$|^ok$|^okay$|^yep$|^sure$|^proceed$|go ahead)"
NO_RE="(^no$|^nope$|^not now$|^later$|^skip$|^no thanks$)"
DONE_RE="(test data (ready|done|filled)|ready|done|filled|proceed|go ahead|continue|next|execute|run)"

# Execution roughness level replies — check LEVEL2 before LEVEL1 since both mention "critical"
LEVEL2_RE="(^2$|critical.*mid|mid.*critical|critical and mid|critical \+ mid)"
LEVEL1_RE="(^1$|^critical$|critical only|just critical|only critical)"
LEVEL3_RE="(^3$|^all$|everything|all tests|^full$)"

# ── WIZARD_OFFER_PENDING: user answered the improvement-wizard question ───────
# pipeline-on-spec-dispatch.sh blocked spec-wizard-generate's default dispatch
# (spec-wizard-pipeline) until this question was asked.
if [[ "$CURRENT_STATE" == "WIZARD_OFFER_PENDING" ]]; then
  SPEC_FILE="$PATH_LINE"

  if echo "$PROMPT" | grep -qiE "$YES_RE"; then
    printf "WIZARD_REQUESTED\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"

    cat <<MSG

╔══════════════════════════════════════════════════════════════╗
║  PIPELINE HOOK — WIZARD REQUESTED                            ║
╠══════════════════════════════════════════════════════════════╣
║  Module : $MODULE
╚══════════════════════════════════════════════════════════════╝

The user wants the improvement wizard. Do NOT retry the test-generation
dispatch yet — instead use the Agent tool now to dispatch spec-wizard-improve:

  CALLER: qa-coordinator
  SPEC_FILE: $SPEC_FILE
  PROJECT_ROOT: $PROJECT

Run the interactive spec improvement wizard on the spec file above.

Wait for its ---WIZARD-COMPLETE--- signal, then retry the exact Stage 1
(test-generation) dispatch you attempted before — it will now be unblocked.

MSG
  elif echo "$PROMPT" | grep -qiE "$NO_RE"; then
    printf "WIZARD_OFFER_ANSWERED\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"

    cat <<MSG

╔══════════════════════════════════════════════════════════════╗
║  PIPELINE HOOK — WIZARD DECLINED                             ║
╠══════════════════════════════════════════════════════════════╣
║  Module : $MODULE
╚══════════════════════════════════════════════════════════════╝

The user declined the improvement wizard. Retry the exact Stage 1
(test-generation) dispatch you attempted before (same prompt, including the
PIPELINE_STAGE: test-generation line) — it is now unblocked. There is no
separate "run the pipeline?" question — continue straight into the pipeline.

MSG
  fi
  # No match: say nothing — the agent re-asks the yes/no question on its own.

# ── QA_PIPELINE_OFFER_PENDING: user answered "run the full QA pipeline?" ─────
# This only ever arises from a standalone spec-wizard-pipeline invocation
# (explicit individual-agent use) — qa-coordinator's own default flow never
# reaches this state, since it has no "run the pipeline?" question at all.
# pipeline-on-spec-dispatch.sh blocked spec-wizard-pipeline's dispatch of
# qa-coordinator until this question was asked.
elif [[ "$CURRENT_STATE" == "QA_PIPELINE_OFFER_PENDING" ]]; then
  SPEC_FILE="$PATH_LINE"

  if echo "$PROMPT" | grep -qiE "$YES_RE"; then
    printf "QA_PIPELINE_CONFIRMED\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"

    cat <<MSG

╔══════════════════════════════════════════════════════════════╗
║  PIPELINE HOOK — QA PIPELINE CONFIRMED                       ║
╠══════════════════════════════════════════════════════════════╣
║  Module : $MODULE
╚══════════════════════════════════════════════════════════════╝

The user confirmed. Retry dispatching qa-coordinator exactly as before (same
prompt, including the PIPELINE_STAGE: pipeline-offer line) — it is now unblocked.

MSG
  elif echo "$PROMPT" | grep -qiE "$NO_RE"; then
    cat <<MSG

The user declined to run the QA pipeline now. Do NOT retry the dispatch —
instead print your skill's Step 4 "no" response (spec complete, reminder of
how to invoke qa-coordinator later) and stop.

MSG
  fi
  # No match: say nothing — the agent re-asks the yes/no question on its own.

# ── GENERATION_COMPLETE: user confirms test data is filled → test-execution ───
elif [[ "$CURRENT_STATE" == "GENERATION_COMPLETE" ]]; then
  MODULE_DIR="$PATH_LINE"

  if echo "$PROMPT" | grep -qiE "$DONE_RE"; then
    printf "TEST_DATA_READY\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"

    SPEC_FILE=$(find "$MODULE_DIR" -maxdepth 1 \( -name "*.spec.md" -o -name "*-description.md" \) 2>/dev/null | head -1)
    TEST_CASES="$MODULE_DIR/test-cases.md"
    TEST_DATA="$MODULE_DIR/test-data.md"

    cat <<MSG

╔══════════════════════════════════════════════════════════════╗
║  PIPELINE HOOK — TEST_DATA_READY                            ║
╠══════════════════════════════════════════════════════════════╣
║  Module : $MODULE
╚══════════════════════════════════════════════════════════════╝

The user has confirmed test data is ready.

Dispatch the **test-execution** agent using the Agent tool with:
  SPEC_FILE       = $SPEC_FILE
  TEST_CASES_FILE = $TEST_CASES
  TEST_DATA_FILE  = $TEST_DATA
  VARS_FILE       = $PROJECT/vars.md
  PROJECT_ROOT    = $PROJECT
  BROWSER_MODE    = headed
  MCP_SERVER      = playwright_headed

MSG
  fi

# ── AWAITING_EXECUTION_LEVEL: user answered the roughness question ────────────
# pipeline-on-execution-dispatch.sh blocked the first dispatch attempt and set
# this state. Resolve the reply to a level (1/2/3) and re-issue the same
# dispatch instruction with EXECUTION_LEVEL added so qa-coordinator can retry.
elif [[ "$CURRENT_STATE" == "AWAITING_EXECUTION_LEVEL" ]]; then
  MODULE_DIR="$PATH_LINE"
  LEVEL=""
  LEVEL_LABEL=""

  if echo "$PROMPT" | grep -qiE "$LEVEL2_RE"; then
    LEVEL="2"; LEVEL_LABEL="Critical + Mid"
  elif echo "$PROMPT" | grep -qiE "$LEVEL1_RE"; then
    LEVEL="1"; LEVEL_LABEL="Critical only"
  elif echo "$PROMPT" | grep -qiE "$LEVEL3_RE"; then
    LEVEL="3"; LEVEL_LABEL="All"
  fi

  if [[ -n "$LEVEL" ]]; then
    printf "TEST_DATA_READY\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"

    SPEC_FILE=$(find "$MODULE_DIR" -maxdepth 1 \( -name "*.spec.md" -o -name "*-description.md" \) 2>/dev/null | head -1)
    TEST_CASES="$MODULE_DIR/test-cases.md"
    TEST_DATA="$MODULE_DIR/test-data.md"

    cat <<MSG

╔══════════════════════════════════════════════════════════════╗
║  PIPELINE HOOK — EXECUTION_LEVEL RESOLVED                   ║
╠══════════════════════════════════════════════════════════════╣
║  Module : $MODULE
║  Level  : $LEVEL — $LEVEL_LABEL
╚══════════════════════════════════════════════════════════════╝

The user answered the execution roughness question.

Retry dispatching the **test-execution** agent using the Agent tool with:
  SPEC_FILE       = $SPEC_FILE
  TEST_CASES_FILE = $TEST_CASES
  TEST_DATA_FILE  = $TEST_DATA
  VARS_FILE       = $PROJECT/vars.md
  PROJECT_ROOT    = $PROJECT
  BROWSER_MODE    = headed
  MCP_SERVER      = playwright_headed
  EXECUTION_LEVEL = $LEVEL

MSG
  fi
  # No match: say nothing — qa-coordinator already told the user valid answers
  # are 1, 2, or 3, so it re-asks for clarification on its own next turn.
fi

exit 0
