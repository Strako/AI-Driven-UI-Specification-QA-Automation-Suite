#!/bin/bash
# PIPELINE HOOK — STATE: GENERATION_COMPLETE
# Fires after every Write tool call.
# Detects when test-cases.md is written inside Platform/ and sets pipeline state.
# qa-coordinator reports Stage 1 completion and attempts the Stage 2 dispatch right
# away; pipeline-on-execution-dispatch.sh reads this GENERATION_COMPLETE state to
# decide whether that dispatch must actually block for test-data confirmation
# (skipped outright when the session is in Claude Code's "auto" permission mode).
#
# Also creates the module's evidences/ subfolder here, deterministically, rather
# than relying on test-execution to create it — that agent has no Bash/mkdir tool,
# only Read/Write/Edit/Glob/Grep/MCP, and Playwright's screenshot call may not
# create missing intermediate directories on its own. Since this hook always
# fires once per module before test-execution ever runs, evidences/ is guaranteed
# to exist by the time the first screenshot is captured.

PROJECT="${PWD}"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0

# Match: Platform/**/test-cases.md
if [[ "$FILE" == "$PROJECT/Platform/"* ]] && \
   [[ "$(basename "$FILE")" == "test-cases.md" ]]; then

  MODULE_DIR=$(dirname "$FILE")
  MODULE=$(basename "$MODULE_DIR")

  # Create the evidences/ subfolder for this module's screenshots up front.
  mkdir -p "$MODULE_DIR/evidences"

  # Persist pipeline state only — qa-coordinator handles the pause message and
  # the pipeline-on-user-prompt hook handles dispatch of test-execution on "done".
  mkdir -p "$(dirname "$STATE_FILE")"
  printf "GENERATION_COMPLETE\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"

fi

exit 0
