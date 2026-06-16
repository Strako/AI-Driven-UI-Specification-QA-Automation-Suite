#!/bin/bash
# PIPELINE HOOK — USER PROMPT SUBMIT
# Fires on every user message.
# Routes pipeline transitions based on current state:
#
#   SPEC_AUTO_GENERATED  + yes  → WIZARD_REQUESTED     → invoke spec-wizard:improve skill
#   SPEC_AUTO_GENERATED  + no   → PIPELINE_OFFER_REQ   → invoke spec-wizard:pipeline-offer skill
#   GENERATION_COMPLETE  + done → TEST_DATA_READY       → dispatch test-execution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# ── SPEC_AUTO_GENERATED: routing handled directly by spec-wizard:auto-generate skill ──
# The skill asks the user about the wizard and dispatches spec-wizard:improve or
# spec-wizard:pipeline-offer itself. State is updated here for tracking only.
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
fi

exit 0
