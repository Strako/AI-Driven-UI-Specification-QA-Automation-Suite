#!/bin/bash
# PIPELINE HOOK — PRE-TOOL-USE ON SPEC-STAGE DISPATCH
# Fires before every Agent-tool dispatch. Gates the two conversational hand-offs
# between spec creation and the QA pipeline, using the same pattern as
# pipeline-on-execution-dispatch.sh: the dispatching agent always attempts the
# default (forward) action immediately, without asking anything first. This hook
# is the only place permission_mode is visible (never exposed to the model), so
# it alone decides: let the dispatch through silently in "auto" mode, or block it
# (exit 2) so the agent asks a human before retrying.
#
#   0. (anything) -> spec-wizard-generate / spec-wizard (legacy)   entry-point redirect to qa-coordinator
#   1. qa-coordinator -> test-generation (Stage 1, only right after a Stage 0
#      bootstrap in the SAME run)   ("run the improvement wizard?" boundary)
#   2. spec-wizard-pipeline -> qa-coordinator   ("run the full QA pipeline?" boundary
#      — only reachable via an EXPLICIT standalone spec-wizard-improve/spec-wizard-pipeline
#      invocation; qa-coordinator's own default flow never goes through this gate,
#      because the default flow always runs the full pipeline unconditionally once
#      qa-coordinator is the entry point — the only question in that flow is whether
#      to pause for the improvement wizard first, never whether to run the pipeline at all)
#
# Also does pure bookkeeping (no gating, always exit 0) for a third case:
# qa-coordinator's Stage 0 bootstrap dispatch to spec-wizard-generate. That run is
# non-interactive by contract regardless of permission_mode, so it must never be
# gated at all — this hook just records a per-module marker file so
# pipeline-on-spec-write-gate.sh can recognize the resulting Write as
# bootstrap-driven and skip its own gate unconditionally.

PROJECT="${PWD}"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" \
  2>/dev/null || echo "")

[[ "$TOOL_NAME" != "Agent" && "$TOOL_NAME" != "Task" ]] && exit 0

PROMPT_TEXT=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('prompt', ti.get('task', ti.get('description',''))))" \
  2>/dev/null || echo "")

SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('subagent_type',''))" \
  2>/dev/null || echo "")

# ── Gate 0: entry-point redirect — qa-coordinator must always receive the ─────
# original request first. Any dispatch of spec-wizard-generate (or its legacy
# alias spec-wizard) that did NOT come from qa-coordinator's own Stage 0
# bootstrap (which always stamps CALLER: qa-coordinator on its dispatch prompt)
# is a direct/top-level invocation bypassing the coordinator — block it and
# redirect. This is a hard block regardless of permission_mode: entry-point
# routing is not a "wait for a human" concern, so auto mode does not bypass it.
if echo "$SUBAGENT_TYPE" | grep -qE '(^|:)spec-wizard-generate$|(^|:)spec-wizard$'; then
  if ! echo "$PROMPT_TEXT" | grep -q "CALLER: qa-coordinator"; then
    cat <<MSG >&2
Do NOT dispatch spec-wizard-generate (or the legacy spec-wizard agent)
directly. Per this plugin's pipeline contract, qa-coordinator must always be
the entry point for a spec-creation request — it bootstraps the spec via
spec-wizard-generate itself (Stage 0) and then continues the rest of the
pipeline deterministically. Dispatch the qa-coordinator agent instead,
passing the user's original request (page/route, module name, credentials,
any stated requirements) verbatim.
MSG
    exit 2
  fi
fi

[[ -z "$PROMPT_TEXT" ]] && exit 0

mkdir -p "$PROJECT/.claude"

# ── Bookkeeping: qa-coordinator's Stage 0 bootstrap dispatch (non-interactive) ──
if echo "$PROMPT_TEXT" | grep -q "CALLER: qa-coordinator" && echo "$PROMPT_TEXT" | grep -q "PAGE_URL:"; then
  MODULE=$(echo "$PROMPT_TEXT" | grep "MODULE_NAME:" | head -1 | sed -E 's/.*MODULE_NAME:[[:space:]]*//' | xargs)
  [[ -n "$MODULE" ]] && touch "$PROJECT/.claude/.spec-bootstrap-${MODULE}"
  exit 0
fi

PERMISSION_MODE=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('permission_mode',''))" \
  2>/dev/null || echo "")

# ── Gate 1: wizard-offer boundary (qa-coordinator -> test-generation, Stage 1) ──
# Only applies when this module's spec was bootstrapped by Stage 0 in THIS run
# (state is still SPEC_AUTO_GENERATED for this exact module) — a pipeline run
# against a pre-existing spec the user pointed to directly never touches this
# gate, matching today's behavior for that case unchanged.
if echo "$PROMPT_TEXT" | grep -qE "PIPELINE_STAGE:[[:space:]]*test-generation"; then
  SPEC_FILE=$(echo "$PROMPT_TEXT" | grep "SPEC_FILE:" | head -1 | sed -E 's/.*SPEC_FILE:[[:space:]]*//' | xargs)
  MODULE_DIR=$(dirname "$SPEC_FILE")
  MODULE=$(basename "$MODULE_DIR")

  # Clear a stale GENERATION_COMPLETE left over from an earlier, never-confirmed
  # generation run for this same module. Otherwise pipeline-on-test-data-edit-gate.sh
  # would mistake this fresh test-generation run's own test-data.md write for an
  # unconfirmed leftover pause and wrongly block it.
  if [[ -f "$STATE_FILE" ]]; then
    STALE_STATE=$(sed -n '1p' "$STATE_FILE" 2>/dev/null)
    STALE_MODULE=$(sed -n '2p' "$STATE_FILE" 2>/dev/null)
    if [[ "$STALE_STATE" == "GENERATION_COMPLETE" && "$STALE_MODULE" == "$MODULE" ]]; then
      rm -f "$STATE_FILE"
    fi
  fi

  # Record that this module's test data was auto-filled by an explicit upfront
  # request (AUTO_FILL_TEST_DATA: true, set only when the user's initial message
  # asked for it — see qa-coordinator's Startup item 5). Per user-guide.md Step
  # 3.5, this is a documented, sanctioned case where the user is still allowed to
  # tweak test-data.md further before execution starts, unlike the default
  # blank-template case pipeline-on-test-data-edit-gate.sh protects. That gate
  # checks for this marker and skips its block when present.
  if echo "$PROMPT_TEXT" | grep -qE "AUTO_FILL_TEST_DATA:[[:space:]]*true"; then
    touch "$PROJECT/.claude/.auto-test-data-${MODULE}"
  fi

  CURRENT_STATE=$(sed -n '1p' "$STATE_FILE" 2>/dev/null)
  STATE_MODULE=$(sed -n '2p' "$STATE_FILE" 2>/dev/null)

  # Not a freshly-bootstrapped spec this run, or already resolved — let through.
  [[ "$STATE_MODULE" != "$MODULE" ]] && exit 0
  [[ "$CURRENT_STATE" != "SPEC_AUTO_GENERATED" ]] && exit 0

  [[ "$PERMISSION_MODE" == "auto" ]] && exit 0

  printf "WIZARD_OFFER_PENDING\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"

  cat <<MSG >&2
Do NOT retry this dispatch yet — the session is not in Claude Code's "auto"
permission mode and the improvement-wizard question has not been asked yet
for the spec you just generated. First stop and ask the user exactly:

  The spec for **$MODULE** has been generated.
  Would you like to run the improvement wizard to review and refine each
  section interactively before continuing into the QA pipeline?

  - yes -> opens the spec improvement wizard, then continues into the pipeline
  - no -> continues straight into the QA pipeline

Wait for their reply. The UserPromptSubmit hook recognizes it and will tell
you whether to dispatch spec-wizard-improve now, or retry this exact
dispatch (test-generation) directly.

Note: there is no separate "run the pipeline?" question anywhere in this
flow — reaching qa-coordinator at all already means the full pipeline runs.
The only choice here is whether to pause for the wizard first.
MSG
  exit 2
fi

# ── Gate 2: pipeline-offer boundary (spec-wizard-pipeline -> qa-coordinator) ──
if echo "$PROMPT_TEXT" | grep -qE "PIPELINE_STAGE:[[:space:]]*pipeline-offer"; then
  SPEC_FILE=$(echo "$PROMPT_TEXT" | grep "SPEC_FILE:" | head -1 | sed -E 's/.*SPEC_FILE:[[:space:]]*//' | xargs)
  MODULE_DIR=$(dirname "$SPEC_FILE")
  MODULE=$(basename "$MODULE_DIR")

  [[ "$PERMISSION_MODE" == "auto" ]] && exit 0

  CURRENT_STATE=$(sed -n '1p' "$STATE_FILE" 2>/dev/null)
  STATE_MODULE=$(sed -n '2p' "$STATE_FILE" 2>/dev/null)

  [[ "$CURRENT_STATE" == "QA_PIPELINE_CONFIRMED" && "$STATE_MODULE" == "$MODULE" ]] && exit 0

  printf "QA_PIPELINE_OFFER_PENDING\n%s\n%s\n" "$MODULE" "$SPEC_FILE" > "$STATE_FILE"

  cat <<MSG >&2
Do NOT retry this dispatch yet — the session is not in Claude Code's "auto"
permission mode and the QA pipeline has not been confirmed yet. First stop
and ask the user exactly what your skill's Step 3 ("Offer the QA Pipeline")
specifies, then wait for their reply (yes to start, no to stop here). The
UserPromptSubmit hook recognizes the reply and will tell you whether to
retry this dispatch or stop.
MSG
  exit 2
fi

exit 0
