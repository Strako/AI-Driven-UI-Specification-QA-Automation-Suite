# Skill: spec-wizard:pipeline-offer

## QA Pipeline Offer

Read the following before doing anything:
1. `SPEC_FILE` (provided in your input) — the completed spec
2. `vars.md` at the project root — extract `BASE_URL`

---

## Step 1 — Parse and Summarize the Spec

Read the spec file and extract:
- View ID and Name
- Route → construct full URL as `BASE_URL + route`
- Number of components
- Total number of fields (across all components + view-level fields)
- Number of screen states
- Number of business rules
- Number of actions
- Related Views (count of spec file entries + external service entries)

---

## Step 2 — Show Spec Summary

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋  SPEC SUMMARY — {Module Name}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
File       : {SPEC_FILE}
View ID    : {<<view-id>>}
Route      : {/route}  →  {https://full-url}

  Components     : {N}
  Fields (total) : {N}
  Screen States  : {N}
  Business Rules : {N}
  Actions        : {N}
  Related Views  : {N spec files, N external services}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Step 3 — Attempt the default dispatch immediately

Do not print any question first. Use the Agent tool right away to dispatch **qa-coordinator**, exactly as if the user had already answered "yes":

```
SPEC_FILE: {absolute path to spec file}
PROJECT_ROOT: {absolute path to project root — directory containing vars.md and TEMPLATE.md}
BROWSER_MODE: headed
PIPELINE_STAGE: pipeline-offer

Run the full QA pipeline for the spec above.
```

The `PreToolUse` hook `pipeline-on-spec-dispatch.sh` is the actual gate for this decision, because it is the only place that can see whether Claude Code's "auto" permission mode is active (you cannot detect this yourself):

- **If the dispatch goes through** — the session is in auto mode. Proceed straight to the full pipeline and wait for qa-coordinator's result normally; do not print the offer below at all.
- **If the dispatch is blocked** — the session is not in auto mode. The hook's feedback tells you to stop and print:

  ```
  🚀  Run the Full QA Pipeline?

    1. Generate test cases  →  test-cases.md  (data-agnostic, all coverage types)
    2. Generate test data   →  test-data.md   (fillable template — you fill values)
    3. Pause for you to fill in test-data.md
    4. Execute all tests via Playwright MCP
    5. Deliver the execution report with PASS / FAIL / BLOCKED breakdown

  Reply  yes  to start, or  no  to stop here.
  ```

  **Do not retry the dispatch until the user replies.** The `UserPromptSubmit` hook recognizes yes/no here and tells you what to do next.

---

## Step 4 — Handle Response

### If the hook tells you the user said **yes**:

Retry the exact same dispatch from Step 3 (including the `PIPELINE_STAGE: pipeline-offer` line) — it is now unblocked.

### If the hook tells you the user said **no**:

Do not retry the dispatch. Print:
```
✅  Spec complete: {SPEC_FILE}

To run the QA pipeline later:
  → Invoke the qa-coordinator agent with SPEC_FILE = {SPEC_FILE}
```

---

## Completion Signal

```
---PIPELINE-OFFER-COMPLETE---
SPEC_FILE: {path}
PIPELINE_REQUESTED: {yes | no}
BROWSER_MODE: headed
---PIPELINE-OFFER-END---
```
