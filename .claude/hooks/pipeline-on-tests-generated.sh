#!/bin/bash
# PIPELINE HOOK — STATE: GENERATION_COMPLETE
# Fires after every Write tool call.
# Detects when test-cases.md is written inside Platform/ and sets pipeline state.
# The qa-coordinator Stage Gate handles the user-facing pause and instructions directly.

PROJECT="/Users/macbookpro/Documents/Projects/Talent-Ai"
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

  # Persist pipeline state only — qa-coordinator handles the pause message and
  # the pipeline-on-user-prompt hook handles dispatch of test-execution on "done".
  mkdir -p "$(dirname "$STATE_FILE")"
  printf "GENERATION_COMPLETE\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"

fi

exit 0
