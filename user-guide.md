# User Guide — QA Automation Suite

Step-by-step walkthrough from a live page URL to a complete test execution report.

---

## Before You Start

Make sure `vars.md` at the project root has your app's base URL and authentication credentials:

```
BASE_URL = https://www.google.com
AUTH_EMAIL = admin@dacodes.com
AUTH_PASSWORD = mypassword123
```

You can define any variable names you want — just reference them by name when invoking the agent:

```
BASE_URL = https://staging.myapp.com
ADMIN_EMAIL = admin@myapp.com
ADMIN_PASSWORD = admin-secret
USER_EMAIL = user@myapp.com
USER_PASSWORD = user-secret
```

> **Security:** Credentials are stored only in `vars.md` and read at runtime. You never type actual passwords in the chat — only variable names like `AUTH_EMAIL` or `AUTH_PASSWORD`.

That is the only manual configuration needed. The `.mcp.json` is already set up with the headed Playwright MCP server.

---

## Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           FULL PIPELINE                                  │
│                                                                          │
│  Step 1              Step 2              Step 3           Step 4         │
│                                                                          │
│  spec-wizard    →  spec-wizard    →  qa-coordinator  →  test-execution   │
│  -generate         -improve           (automated)       (automated)      │
│  (automated)       (you + AI)              │                  │          │
│       │                 │                  │                  │          │
│  {module}-         refined spec      test-cases.md     test-report-      │
│  description.md                      test-data.md      {module}.md       │
│                                      [YOU FILL THIS]   screenshots/      │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1 — Auto-Generate the Spec

The auto-generator navigates to your live page using Playwright MCP, analyzes the full DOM (scrolling, tabs, expandable sections), and produces a complete spec file in one pass.

### Invoke the agent

In Claude Code, switch to the `spec-wizard-generate` agent and describe what you need. You can front-load all inputs in one message:

```
Create a spec for /dashboard.
Login is at /login — credentials: email: AUTH_EMAIL, password: AUTH_PASSWORD
Destination after login: /dashboard
Module name: dashboard
```

Or include a design reference for design-vs-implementation comparison:

```
Create a spec for /dashboard.
Login is at /login — credentials: email: AUTH_EMAIL, password: AUTH_PASSWORD
Destination after login: /dashboard
Module name: dashboard
Design reference: https://www.figma.com/design/abc123/MyProject?node-id=1234-5678
```

Or with a Pencil slide name:

```
Create a spec for /login
Design reference: Login Screen
```

Or just provide the minimum and the agent will ask for the rest:

```
Create a spec for /dashboard
```

> **Note:** Credentials are never typed directly in the prompt. Instead, you reference variable names from `vars.md` (e.g. `AUTH_EMAIL`, `AUTH_PASSWORD`). The agent reads the actual values from `vars.md` at runtime. This keeps sensitive data out of chat history.

### Inputs collected

| Input               | Required | Description                                                                                                                                                               |
| ------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PAGE_URL`          | Yes      | Route or full URL of the page to analyze (e.g. `/dashboard`)                                                                                                              |
| `MODULE_NAME`       | No       | Short kebab-case name — derived from URL if omitted                                                                                                                       |
| `AUTH_REQUIRED`     | No       | Whether the page needs authentication first                                                                                                                               |
| `LOGIN_ROUTE`       | If auth  | Route of the login page (e.g. `/login`)                                                                                                                                   |
| `AUTH_EMAIL_VAR`    | If auth  | Variable name in `vars.md` for login email/username (e.g. `AUTH_EMAIL`). Credentials are never hardcoded — always read from `vars.md`.                                    |
| `AUTH_PASSWORD_VAR` | If auth  | Variable name in `vars.md` for login password (e.g. `AUTH_PASSWORD`). Credentials are never hardcoded — always read from `vars.md`.                                       |
| `DESTINATION_ROUTE` | If auth  | Page to analyze after login (defaults to `PAGE_URL`)                                                                                                                      |
| `OUTPUT_DIR`        | No       | Where to save (default: `Platform/{ModuleName}/`)                                                                                                                         |
| `DESIGN_REFERENCE`  | No       | Pencil slide name or Figma frame URL for design comparison. When provided, enables a Design Comparison test case that compares the live page against the original design. |

> All routes starting with `/` are automatically resolved as `BASE_URL + route` using `vars.md`.

### What happens

After you confirm the inputs, the agent:

1. **Reads `vars.md`** — extracts `BASE_URL` and credential values for the variable names you specified
2. **Authenticates** (if required) — navigates to login, fills credentials from `vars.md`, submits
3. **Navigates** to the target page
4. **Captures** a screenshot (`{module}-analysis.png`) and the full accessibility tree
5. **Scrolls** through the page and interacts with tabs/expandable sections
6. **Analyzes** the DOM to identify components, fields, actions, and states
7. **Generates** the complete spec following `TEMPLATE.md` format
8. **Saves** to `Platform/{ModuleName}/{module}-description.md`

Then prints:

```
✅  Spec saved: Platform/Dashboard/dashboard-description.md
```

And asks:

```
The spec for dashboard has been generated.
Would you like to run the improvement wizard to review and refine each section interactively?
- yes → opens the spec improvement wizard
- no → goes straight to the QA pipeline offer
```

---

## Step 2 — Improve the Spec (Optional but Recommended)

If you replied **yes**, the `spec-wizard-improve` agent launches. It walks through all 9 sections of your spec one at a time.

### How the wizard works

For each section, the wizard:

1. Shows the current content in exact spec format
2. Asks targeted questions about what the AI couldn't infer
3. Applies your changes and shows the updated draft
4. Waits for you to type `next`, `yes`, or `skip` before advancing

### Section-by-section questions

**Section 1 — Screen Identification**

> Is the View ID, Name, Version, and Route correct?

**Section 2 — Origin Context**

> What view does the user come FROM? What's the start flow?

**Section 3 — Components** (most important — one component at a time)

> 1. Is there a component-level validation?
> 2. For each field — what validation rule and error message apply?
> 3. Are any fields marked as required that weren't detected?
> 4. Did I miss any fields?
> 5. Should any fields be renamed?
> 6. Is the component name and role correct?
>
> After all components: "Are there additional components I missed?"

**Section 4 — View-Level Fields**

> Global banners, floating buttons outside components?

**Section 5 — Screen States**

> Transitions and conditions for each state (loading, error, empty…)

**Section 6 — Related Views**

> Dependencies on other spec files? External services (OAuth, Stripe…)?

**Section 7 — Business Rules**

> Role-based access, data limits, status gates, ownership rules?

**Section 8 — Actions & Transitions**

> Exact transition target and expected reaction for each button/link?

**Section 9 — Detailed Flow Description**

> Review and correct the AI-generated narrative.

### Final review and save

After all 9 sections, the wizard shows the complete updated spec and asks for confirmation. Once saved, it automatically launches `spec-wizard-pipeline`.

---

## Step 3 — Pipeline Offer and Test Generation

Whether you came from the improvement wizard or skipped it, `spec-wizard-pipeline` shows a structured summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋  SPEC SUMMARY — Dashboard
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
File       : Platform/Dashboard/dashboard-description.md
View ID    : <<dashboard-3f2c1a9b-...>>
Route      : /dashboard  →  https://www.google.com/dashboard

  Components     : 3
  Fields (total) : 12
  Screen States  : 4
  Business Rules : 2
  Actions        : 6
  Related Views  : 1 spec files, 0 external services
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚀  Run the Full QA Pipeline?
Reply yes to start, or no to stop here.
```

If you reply **yes**, the `qa-coordinator` is dispatched and test generation begins.

### What `test-generation` produces

The agent reads your spec and `vars.md`, then writes two files:

**`test-cases.md`** — complete, data-agnostic test cases

Every interactive element is referenced as `${field-name}` — never a hardcoded value:

```markdown
## [TC-SMK-01] Dashboard view loads correctly

- **Type**: Smoke
- **Preconditions**: The user is authenticated and navigates to
  https://www.google.com/dashboard
- **Steps**:
  1. Navigate to `BASE_URL + /dashboard`
  2. Verify that `<<stats-panel-...>>` is visible
  3. Verify that `<<jobs-table-...>>` is visible
- **Expected Result**: All main components are visible without errors
```

Coverage generated: **Happy Path · Smoke · Functional · Edge Cases · Exploratory**

**`test-data.md`** — empty template organized by scenario

```markdown
# Test Data — <<dashboard-3f2c1a9b-...>>

## [TC-HP-01] Job search works correctly

### <<dashboard-3f2c1a9b-...>>

- ${jobs-search}:
- ${jobs-status-filter}:
```

After both files are written, the coordinator pauses:

```
✅ Stage 1 complete — Test cases generated.

  test-cases.md  → 24 cases (Smoke: 3, HP: 2, Functional: 9, Edge: 6, Exploratory: 4)
  test-data.md   → 14 scenarios

Before execution, fill in the test data:
📄 Platform/Dashboard/test-data.md

Reply here when you are ready to continue.
```

---

## Step 4 — Fill `test-data.md`

Open `Platform/Dashboard/test-data.md` and replace every empty `${field-name}:` slot with a real value.

```markdown
## [TC-HP-01] Job search works correctly

### <<dashboard-3f2c1a9b-...>>

- ${jobs-search}: developer
- ${jobs-status-filter}: published

## [TC-FN-03] Status filter shows drafts

### <<dashboard-3f2c1a9b-...>>

- ${jobs-status-filter}: draft

## [TC-EC-01] Search with no-results term

### <<dashboard-3f2c1a9b-...>>

- ${jobs-search}: xqzjklmnop
```

**Rules for filling test data:**

| Scenario type         | What value to use                                               |
| --------------------- | --------------------------------------------------------------- |
| Happy Path            | Valid data that should succeed                                  |
| Functional (negative) | Invalid data that triggers the validation being tested          |
| Edge Case             | Boundary values — empty strings, max length, special characters |
| Exploratory           | Unusual but plausible values                                    |

> Tests that have no interactive fields (pure visibility/smoke checks) do not appear in `test-data.md` — there is nothing to fill for them.

When done, reply in Claude:

```
Done, test data is filled.
```

The pipeline hook detects your confirmation and automatically dispatches test execution.

---

## Step 5 — Test Execution (including Design Comparison)

The `test-execution` agent works through every test case sequentially:

1. Reads `test-cases.md`, `test-data.md`, `vars.md`, and the spec file
2. **Hydrates** each test case — replaces every `${field-name}` with the concrete value you filled in
3. For each test case:
   - `browser_navigate` → goes to the precondition URL
   - `browser_snapshot` → reads the DOM, gets element `ref=` values
   - `browser_type` → fills inputs
   - `browser_click` → clicks buttons using their `ref=`
   - `browser_take_screenshot` → captures evidence
4. Classifies each result: **✅ PASS · ❌ FAIL · ⚠️ BLOCKED**
5. Writes `Platform/Dashboard/test-report-dashboard.md`

### Design Comparison (TC-DC test cases)

If a `Pencil slide name / Figma frame URL` was provided in the spec's Screen Identification, the test generation step will have created a **TC-DC-01** test case. During execution, the agent:

1. Navigates to the page and takes a full screenshot
2. Retrieves the original design:
   - **Figma URL** → uses Figma MCP (`get_node`) to fetch the frame's visual structure
   - **Pencil slide name** → uses Pencil MCP (`batch_get`) to locate and read the slide
3. Compares the live page against the design across 6 dimensions: structure/layout, typography, colors, spacing, components, and images/icons
4. Classifies each discrepancy by severity: **Critical · Major · Minor · Cosmetic**
5. Documents all findings in a dedicated **DESIGN COMPARISON** section of the report

The TC-DC test case passes only if zero critical or major discrepancies are found.

### Result classification

| Status     | When                                                                        |
| ---------- | --------------------------------------------------------------------------- |
| ✅ PASS    | All steps completed and the expected result matched observed behavior       |
| ❌ FAIL    | One or more steps did not produce the expected result                       |
| ⚠️ BLOCKED | Test could not run — missing data, environment issue, or tooling limitation |

### What the report looks like

```markdown
# Test Execution Report — Dashboard

**URL:** `https://www.google.com/dashboard`
**Date:** 2026-05-20
**Executed with:** Playwright MCP — server `playwright_headed`

---

## Executive Summary

| Category          | Total  | ✅ Passed | ❌ Failed | ⚠️ Blocked |
| ----------------- | ------ | --------- | --------- | ---------- |
| Smoke Tests       | 3      | 3         | 0         | 0          |
| Happy Path        | 2      | 2         | 0         | 0          |
| Functional Tests  | 9      | 7         | 2         | 0          |
| Edge Cases        | 6      | 5         | 0         | 1          |
| Exploratory Tests | 4      | 3         | 1         | 0          |
| Design Comparison | 1      | 0         | 1         | 0          |
| **TOTAL**         | **25** | **20**    | **4**     | **1**      |

**Success rate: 20/25 (80%)**

---

## SMOKE TESTS (3/3 ✅) ...

## HAPPY PATH (2/2 ✅) ...

## FUNCTIONAL TESTS (7/9 — 2 failed) ...

## EDGE CASES (5/6 — 1 blocked) ...

## EXPLORATORY TESTS (3/4 — 1 failed) ...

## DESIGN COMPARISON (0/1 — 1 failed)

### Design Reference

- **Source**: https://www.figma.com/design/abc123/MyProject?node-id=1234-5678
- **Comparison date**: 2026-05-20

### Discrepancy Summary

| Category   | Discrepancies | Critical Severity | Major Severity | Minor Severity | Cosmetic |
| ---------- | ------------- | ----------------- | -------------- | -------------- | -------- |
| Typography | 2             | 0                 | 1              | 1              | 0        |
| Colors     | 1             | 0                 | 0              | 1              | 0        |
| Spacing    | 1             | 0                 | 1              | 0              | 0        |
| **TOTAL**  | **4**         | **0**             | **2**          | **2**          | **0**    |

### Discrepancy Details

#### Typography — Main title

- **Severity**: Major
- **In the design**: Font-size 32px, font-weight 700, color #1A1A1A
- **In the implementation**: Font-size 28px, font-weight 600, color #333333
- **Affected component**: `<<stats-panel-...>>`
- **Evidence**: TC-DC-01-typography-title.png

## Failure Details

### TC-FN-05 — Status filter shows only drafts

**Step where error occurred:** Step 3
**Expected result:** Table shows only jobs with draft status
**Actual result:** Table showed jobs in all statuses
**Failure reason:** The status filter does not apply the parameter correctly
**Evidence:** TC-FN-05-status-filter-failure.png

## Captured Screenshots

| File                                 | Description                     |
| ------------------------------------ | ------------------------------- |
| `TC-SMK-01-page-loaded.png`          | Dashboard main view             |
| `TC-HP-01-search-success.png`        | Filtered search results         |
| `TC-FN-05-status-filter-failure.png` | Status filter failure           |
| `TC-DC-01-current-page.png`          | Page screenshot for comparison  |
| `TC-DC-01-typography-title.png`      | Typography discrepancy in title |
```

---

## Output Files Per Module

After the full pipeline, your module folder contains:

```
Platform/Dashboard/
├── dashboard-description.md        ← spec (created by spec-wizard-generate)
├── dashboard-analysis.png          ← screenshot from auto-generation analysis
├── test-cases.md                   ← generated test cases
├── test-data.md                    ← filled test data
├── test-report-dashboard.md        ← execution report
└── TC-*.png                        ← screenshot evidence per test
```

---

## Running the Pipeline Manually

You don't have to go through the full flow every time. Here's how to invoke each stage independently:

### Create a spec (auto-generate only)

```
Invoke: spec-wizard-generate
"Create a spec for /jobs, module name vacantes"
```

### Improve an existing spec

```
Invoke: spec-wizard-improve
"Improve Platform/Login/login-description.md"
```

### Full pipeline on an existing spec

```
Invoke: qa-coordinator
"Run the full QA pipeline for Platform/Login/login-description.md"
```

### Generate test cases only

```
Invoke: qa-coordinator
"Generate test cases only for Platform/Dashboard/dashboard-description.md"
```

### Execute already-filled tests

```
Invoke: qa-coordinator
"Execute tests for Platform/Login/login-description.md"
```

---

## Quick Reference

| You want to…                           | Agent                  | Message                                                                                           |
| -------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------- |
| Auto-generate a spec from a live page  | `spec-wizard-generate` | `"Create a spec for /dashboard, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD"` |
| Auto-generate with design comparison   | `spec-wizard-generate` | `"Create a spec for /dashboard, design reference: https://figma.com/design/...?node-id=..."`      |
| Auto-generate with Pencil design       | `spec-wizard-generate` | `"Create a spec for /login, design reference: Login Screen"`                                      |
| Improve an existing spec interactively | `spec-wizard-improve`  | `"Improve Platform/Dashboard/dashboard-description.md"`                                           |
| See spec summary + offer pipeline      | `spec-wizard-pipeline` | `"Summarize Platform/Dashboard/dashboard-description.md"`                                         |
| Full pipeline on an existing spec      | `qa-coordinator`       | `"Run the full QA pipeline for Platform/Dashboard/dashboard-description.md"`                      |
| Generate test cases only               | `qa-coordinator`       | `"Generate test cases only for Platform/Dashboard/dashboard-description.md"`                      |
| Execute already-filled tests           | `qa-coordinator`       | `"Execute tests for Platform/Dashboard/dashboard-description.md"`                                 |
| Create spec without login              | `spec-wizard-generate` | `"Create a spec for /jobs, module name vacantes"`                                                 |
| Use legacy wizard (full interview)     | `spec-wizard`          | `"Create a spec for /dashboard"`                                                                  |

---

## Tips

- **All output goes to `Platform/`** — every module gets its own subfolder under `Platform/`. This keeps specs, test cases, and reports organized by screen.

- **Design comparison** — provide a Figma frame URL or Pencil slide name when creating a spec to enable automatic design-vs-implementation comparison. The system will retrieve the design using the appropriate MCP tool (Figma MCP for Figma URLs, Pencil MCP for Pencil slide names) and compare it against the live page during test execution. Discrepancies are classified by severity and documented in the report.

- **Headed mode only** — the system always uses the headed Playwright browser (`playwright_headed`). You can watch the browser during execution, which is useful when debugging failures.

- **Re-running after a fix** — invoke `qa-coordinator` with "Execute tests for …" (execute-only mode). No need to regenerate test cases unless the spec changed.

- **Updating the spec** — run `spec-wizard-improve` on the existing file. Then re-run `qa-coordinator` to regenerate test cases from the updated spec.

- **Multiple modules** — each module lives in its own `Platform/{ModuleName}/` folder. Run the pipeline on any of them independently.

- **Changing the base URL** — edit `vars.md`. All agents pick it up automatically on their next run.

- **Credentials management** — store all login credentials in `vars.md` as named variables (e.g. `AUTH_EMAIL = admin@example.com`). When invoking agents, reference them by variable name only (e.g. `email: AUTH_EMAIL, password: AUTH_PASSWORD`). This keeps sensitive data out of chat history and makes it easy to switch environments.

- **Pipeline state** — the `.claude/.pipeline-state` file tracks where you are in the pipeline. If something gets stuck, you can delete this file to reset state and start fresh.

- **No programmatic Playwright** — the system never writes or runs Playwright code. All browser automation happens through MCP tool calls. This means no `node_modules`, no test scripts, no `npx playwright` commands.
