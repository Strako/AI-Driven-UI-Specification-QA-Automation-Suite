#!/bin/bash
# PIPELINE HOOK — USER PROMPT SUBMIT
# Fires on every user message.
# Routes pipeline transitions based on current state:
#
#   SPEC_AUTO_GENERATED       + yes    → WIZARD_REQUESTED     → dispatch spec-wizard-improve agent
#   SPEC_AUTO_GENERATED       + no     → PIPELINE_OFFER_REQ   → dispatch spec-wizard-pipeline agent
#   GENERATION_COMPLETE       + done   → TEST_DATA_READY       → dispatch test-execution
#   AWAITING_EXECUTION_LEVEL  + 1/2/3  → TEST_DATA_READY       → retry test-execution dispatch with EXECUTION_LEVEL set

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

# ── SPEC_AUTO_GENERATED: routing handled directly by spec-wizard-generate itself ──
# The agent asks the user about the wizard and dispatches spec-wizard-improve or
# spec-wizard-pipeline itself via the Agent tool. State is updated here for tracking only.
if [[ "$CURRENT_STATE" == "SPEC_AUTO_GENERATED" ]]; then
  SPEC_FILE="$PATH_LINE"

  if echo "$PROMPT" | grep -qiE "$YES_RE"; then
    printf "WIZARD_REQUESTED\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"
  elif echo "$PROMPT" | grep -qiE "$NO_RE"; then
    printf "PIPELINE_OFFER_REQUESTED\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"
  fi

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
