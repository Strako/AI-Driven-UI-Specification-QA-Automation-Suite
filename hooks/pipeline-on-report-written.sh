#!/bin/bash
# PIPELINE HOOK — STATE: EXECUTION_COMPLETE
# Fires after every Write tool call.
# Detects when a test-report-*.md is written inside Platform/ and sets pipeline state.
# The test-execution skill outputs its own ---EXECUTION-COMPLETE--- block and summary directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0

# Match: Platform/**/test-report-*.md
if [[ "$FILE" == "$PROJECT/Platform/"* ]] && \
   [[ "$(basename "$FILE")" =~ ^test-report-.*\.md$ ]]; then

  MODULE_DIR=$(dirname "$FILE")
  MODULE=$(basename "$MODULE_DIR")

  # Mark pipeline as complete — test-execution skill handles its own output and summary.
  mkdir -p "$(dirname "$STATE_FILE")"
  printf "EXECUTION_COMPLETE\n%s\n%s\n" "$MODULE" "$FILE" > "$STATE_FILE"

fi

exit 0
