#!/bin/bash
# PIPELINE HOOK — SPEC WRITTEN (PostToolUse Write)
# Fires after every Write tool call.
# Detects when a spec file is written inside Platform/ and routes based on pipeline state:
#   - WIZARD_REQUESTED state → wizard just finished → set WIZARD_COMPLETE → trigger pipeline-offer skill
#   - Any other state       → auto-gen just wrote spec → set SPEC_AUTO_GENERATED → offer wizard

PROJECT="/Users/macbookpro/Documents/Projects/Talent-Ai"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0

# Match: Platform/**/*.spec.md  or  Platform/**/*-description.md
if [[ "$FILE" == "$PROJECT/Platform/"* ]] && \
   { [[ "$FILE" =~ \.spec\.md$ ]] || [[ "$FILE" =~ \-description\.md$ ]]; }; then

  MODULE_DIR=$(dirname "$FILE")
  MODULE=$(basename "$MODULE_DIR")

  mkdir -p "$(dirname "$STATE_FILE")"

  # Read current state to distinguish auto-gen write vs wizard write
  CURRENT_STATE=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || echo "")

  if [[ "$CURRENT_STATE" == "WIZARD_REQUESTED" ]]; then
    # ── The improvement wizard just finished writing the spec ──────────────────
    printf "WIZARD_COMPLETE\n%s\n%s\n" "$MODULE" "$FILE" > "$STATE_FILE"
    # State updated — spec-wizard:improve handles dispatch to pipeline-offer directly.

  else
    # ── Auto-generator just wrote the spec for the first time ─────────────────
    printf "SPEC_AUTO_GENERATED\n%s\n%s\n" "$MODULE" "$FILE" > "$STATE_FILE"
    # State updated — spec-wizard:auto-generate handles the wizard offer and dispatch directly.

  fi
fi

exit 0
