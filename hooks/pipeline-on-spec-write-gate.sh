#!/bin/bash
# PIPELINE HOOK — PRE-TOOL-USE ON SPEC WRITE (DOCS/ ENRICHMENT GATE)
# Fires before every Write tool call. Gates only the very first save of a brand
# new module's spec file — the moment spec-wizard-generate's Phase REQUIREMENTS
# applies — so that a project's docs/ folder is deterministically checked and
# applied before the spec ever lands on disk, instead of depending on the model
# to remember to check it.
#
# Unlike the old interactive design, this is NOT a user-facing question and
# does NOT depend on permission_mode at all: this hook itself checks whether
# docs/*.md or docs/*.csv exist. If they don't, there is nothing to apply and
# the Write proceeds immediately, in every mode, for every caller. If they do,
# the Write is blocked exactly once so the agent reads and applies them, then
# retries — no human is ever asked anything here.
#
# "First save of a brand new module" is detected structurally: the spec file
# does not exist on disk yet. Any later Write to the same path — a resave by
# the improvement wizard (spec-wizard-improve), or anything else — is left
# completely untouched, since Phase REQUIREMENTS is a one-time, pre-save step
# that conceptually cannot apply to a file that already exists.

PROJECT="${PWD}"

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0

# Only the spec file itself, and only inside Platform/.
if [[ "$FILE" != "$PROJECT/Platform/"* ]] || \
   { ! [[ "$FILE" =~ \.spec\.md$ ]] && ! [[ "$FILE" =~ \-description\.md$ ]]; }; then
  exit 0
fi

# Already exists on disk -- this is a resave (e.g. the improvement wizard), not
# a first-time creation. Phase REQUIREMENTS never applies here. Let it through.
[[ -f "$FILE" ]] && exit 0

MODULE_DIR=$(dirname "$FILE")
MODULE=$(basename "$MODULE_DIR")

mkdir -p "$PROJECT/.claude"

DOCS_MARKER="$PROJECT/.claude/.docs-enrichment-applied-${MODULE}"
[[ -f "$DOCS_MARKER" ]] && exit 0

DOCS_DIR="$PROJECT/docs"
DOCS_FOUND=$(find "$DOCS_DIR" -maxdepth 1 \( -iname "*.md" -o -iname "*.csv" \) -print -quit 2>/dev/null)

# No docs/ folder, or it exists but has nothing readable in it -- nothing to
# apply. Let the Write through immediately, no block, no question, ever.
[[ -z "$DOCS_FOUND" ]] && exit 0

touch "$DOCS_MARKER"

cat <<MSG >&2
Do NOT write the spec file yet — a docs/ folder exists at the project root
with requirement files. Before saving, scan every .md and .csv file in
$DOCS_DIR, identify requirements relevant to this module (matched by module
name, route, component names, or feature keywords inferred from the DOM
analysis), apply the relevant ones to the in-memory spec draft per Phase
REQUIREMENTS in your skill file, print the enrichment summary, then retry
this Write — it is now unblocked. This does not require asking the user
anything; it is a deterministic, silent step.
MSG
exit 2
