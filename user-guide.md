# User Guide — QA Automation Suite

Step-by-step walkthrough from a live page URL to a complete test execution report.

---

## Before You Start

### Installation

If you haven't installed the plugin yet, run:

```bash
# Step 1 — add the marketplace (one-time per machine)
claude plugin marketplace add Strako/AI-Driven-UI-Specification-QA-Automation-Suite

# Step 2 — install the plugin into your project
claude plugin install AI-Driven-UI-Specification
```

This copies all agents, skills, hooks, settings, and root files into your project automatically. See [INSTALL.md](INSTALL.md) or the [README](README.md) for manual installation and prerequisites.

### Configure vars.md

After installation (or cloning), open `vars.md` at your project root and fill in your app's credentials:

```
BASE_URL = https://your-app.example.com
AUTH_EMAIL = admin@your-app.example.com
AUTH_PASSWORD = your-password
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

> **Persistent test identity.** If you leave `AUTH_EMAIL` / `AUTH_PASSWORD` as the placeholder values shown above, both `test-execution` and `spec-wizard-generate` (when run with `AUTH_MODE=new`, Step 1) treat them as unset. The first time either flow needs to create an account, it generates a `@yopmail.com` test identity, verifies it via Yopmail, and overwrites these two lines with the real values — every later run of either flow reuses that same account instead of signing up again. To force a fresh account, restore the placeholder values. See **Persistent Test Identity & Email Verification** under Step 5.

`vars.md` and `.mcp.json` are the only required configurations. Both are placed at your project root by the plugin installer.

### Create the output directory

```bash
mkdir -p Platform
```

All specs, test cases, and reports are saved under `Platform/{ModuleName}/`.

### Figma access token (optional — for design comparison)

If you plan to provide a Figma frame URL as a design reference, set your Figma personal access token once in your shell profile:

```bash
# Add to ~/.zshrc or ~/.bashrc
export FIGMA_ACCESS_TOKEN=fig_xxxxxxxxxxxxx
```

Then reload your shell (`source ~/.zshrc`) or open a new terminal. No per-project setup needed — the token is picked up automatically from your OS environment.

Generate a token from: Figma → Settings → Personal access tokens.

> If `FIGMA_ACCESS_TOKEN` is missing, the Figma MCP server simply won't start — Playwright still works, Figma features don't. You only need this token when using Figma URLs as design references.

---

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FULL PIPELINE                                  │
│                                                                             │
│  Step 1          Step 1.5        Step 2          Step 3        Step 4       │
│                                                                             │
│  spec-wizard  → requirements  → spec-wizard  → qa-coord   → test-exec      │
│  -generate      enrichment      -improve       (automated)   (automated)   │
│  (automated)    (you + AI)      (you + AI)         │              │         │
│       │              │               │              │              │         │
│  spec in       refined spec    saved spec      test-cases    test-report    │
│  memory        in memory       on disk         test-data     screenshots    │
│                [optional]      [YOU FILL       [YOU FILL                    │
│                                  this]          this]                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

> Between Step 3 and Step 4, an optional **Step 4.5 — Execution Roughness Gate** may pause the pipeline to ask how much of the suite to run — skipped when you're in Claude Code's auto permission mode or you already stated a level.

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

| Input | Required | Description |
|---|---|---|
| `PAGE_URL` | Yes | Route or full URL of the page to analyze (e.g. `/dashboard`) |
| `MODULE_NAME` | No | Short kebab-case name — derived from URL if omitted |
| `AUTH_REQUIRED` | No | Whether the page needs an authenticated session first |
| `AUTH_MODE` | If auth | `existing` (default) — log in with an account already configured in `vars.md`. `new` — no account exists yet; create one first via Yopmail (see below). |
| `LOGIN_ROUTE` | If `existing` | Route of the login page (e.g. `/login`) |
| `SIGNUP_ROUTE` | If `new` | Route of the signup/registration page (e.g. `/signup`) |
| `AUTH_EMAIL_VAR` | If auth | Variable name in `vars.md` for the email/username (e.g. `AUTH_EMAIL`). Credentials are never hardcoded — always read from (and for `new`, written to) `vars.md`. |
| `AUTH_PASSWORD_VAR` | If auth | Variable name in `vars.md` for the password (e.g. `AUTH_PASSWORD`). Omit for `AUTH_MODE=new` passwordless signups. Credentials are never hardcoded. |
| `DESTINATION_ROUTE` | If auth | Page to analyze after login or account creation (defaults to `PAGE_URL`) |
| `OUTPUT_DIR` | No | Where to save (default: `Platform/{ModuleName}/`) |
| `DESIGN_REFERENCE` | No | Pencil slide name or Figma frame URL for design comparison. When provided, enables a Design Comparison test case that compares the live page against the original design. |

> All routes starting with `/` are automatically resolved as `BASE_URL + route` using `vars.md`.

> **New account (`AUTH_MODE=new`).** If the named `vars.md` variables are still placeholders (or blank), the agent generates a fresh `qa-{random}@yopmail.com` identity, submits the signup form with it, confirms any OTP/confirmation link via a second-tab Yopmail check, and persists the result to `vars.md` for future runs — see **Persistent Test Identity & Email Verification** under Step 5, which describes the exact same procedure this agent follows.

### What happens

After you confirm the inputs, the agent:

1. **Reads `vars.md`** — extracts `BASE_URL` and credential values for the variable names you specified
2. **Authenticates** (if required) — navigates to login, fills credentials from `vars.md`, submits
3. **Navigates** to the target page
4. **Captures** a screenshot (`{module}-analysis.png`) and the full accessibility tree
5. **Scrolls** through the page and interacts with tabs/expandable sections
6. **Analyzes** the DOM to identify components, fields, actions, and states
7. **Generates** the complete spec in memory following `TEMPLATE.md` format
8. **Asks about requirements enrichment** (see Step 1.5 below)
9. **Saves** the enriched spec to `Platform/{ModuleName}/{module}-description.md`

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

## Step 1.5 — Requirements Enrichment (Optional)

Before writing the spec to disk, the agent offers to enrich the generated spec with project requirements or user stories. This step refines the spec in memory using your existing documentation, so the saved file already incorporates known business requirements.

### The prompt you will see

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋  REQUIREMENTS ENRICHMENT (optional)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The spec has been generated from the live page.
Before saving, would you like to enrich it with project requirements?

  • Provide a file path  —  path to an .xlsx, .csv, or .md file containing
    user stories or requirements for the platform

  • Type  docs  —  auto-scan the docs/ folder at the project root

  • Type  skip  —  save the spec as-is without requirements enrichment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Option A — Provide a file path

Type the path to your requirements file:

```
/path/to/requirements.md
```

Accepted formats:

| Format | How it is read |
|---|---|
| `.md` | Read directly — user stories, acceptance criteria, feature descriptions |
| `.csv` | Read directly — each row treated as a requirement |
| `.xlsx` | Binary format — agent will ask you to re-export as `.csv` or `.md` first |

The agent reads the file, identifies requirements **relevant to this specific view** (matched by module name, route, component names, or feature keywords), and applies them to the in-memory spec:

- Adds missing fields mentioned in requirements
- Adds business rules derived from acceptance criteria
- Adds screen states and actions described in user stories
- Expands the Detailed Flow Description with requirement-driven scenarios

After enrichment, the agent prints a summary:

```
✅  Requirements enrichment applied

  Source          : /path/to/requirements.md
  Relevant items  : 7 requirements matched to dashboard
  Changes applied :
    • Added field ${dashboard-active-jobs-count} to Stats Panel component
    • Added business rule: Only admin users may access this view
    • Added screen state: empty (no active jobs)
```

### Option B — Type `docs`

If you have requirement files in a `docs/` folder at your project root, type `docs`. The agent scans all `.md` and `.csv` files in that folder, extracts requirements relevant to this view, and applies the same enrichment.

> The agent locates "project root" by finding `vars.md` via a Glob search — so your `docs/` folder just needs to sit next to `vars.md`. If `docs/` does not exist or is empty, the agent prints `⚠️  No files found in docs/. Saving spec as generated.` and continues without failing.

```
docs/
├── requirements.md          ← scanned automatically
├── user-stories.md          ← scanned automatically
└── acceptance-criteria.csv  ← scanned automatically
```

### Option C — Type `skip`

Saves the spec exactly as generated from the DOM analysis. You can still refine it manually in Step 2 (the improvement wizard).

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
Route      : /dashboard  →  https://your-app.example.com/dashboard

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

The agent reads your spec (and any related spec files), then writes two files:

**`test-cases.md`** — complete, data-agnostic test cases

Every interactive element is referenced as `${field-name}` and every navigation as `<<view-id>>` / `{{BASE_URL}}` — never a hardcoded value or domain. `test-generation` never reads `vars.md`; `BASE_URL` is only resolved later, by `test-execution`, so the same test cases run against any environment without regeneration.

Coverage generated: **Happy Path · Smoke · Functional · Edge Cases · Exploratory**

Every test case is also assigned a **Severity** — Critical, Mid, or Low — judged by business impact (the happy path and smoke checks are typically Critical; edge cases and exploratory scenarios are typically Low). This severity is what Step 4.5 uses to scope how much of the suite actually runs.

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
                   Severity: 6 Critical, 15 Mid, 3 Low
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

## [TC-EC-01] Search with no-results term

### <<dashboard-3f2c1a9b-...>>

- ${jobs-search}: xqzjklmnop
```

**Rules for filling test data:**

| Scenario type | What value to use |
|---|---|
| Happy Path | Valid data that should succeed |
| Functional (negative) | Invalid data that triggers the validation being tested |
| Edge Case | Boundary values — empty strings, max length, special characters |
| Exploratory | Unusual but plausible values |

> Tests that have no interactive fields (pure visibility/smoke checks) do not appear in `test-data.md` — there is nothing to fill for them.

When done, reply in Claude:

```
Done, test data is filled.
```

The pipeline hook detects your confirmation and automatically attempts to dispatch test execution.

---

## Step 4.5 — Execution Roughness Gate (conditional)

Before test-execution actually starts, a hook checks whether your Claude Code session is running in **auto** permission mode.

- **If you already stated a level** when you started the pipeline (e.g. "...just run the critical tests"), this step is skipped entirely — your choice is used, whether or not auto mode is on.
- **If you're in auto mode** and said nothing, this step is also skipped — the pipeline defaults to running **all** test cases.
- **Otherwise**, the dispatch is paused and you're asked directly:

  ```
  Before executing, how thorough should this run be?

  1 — Critical only (6 tests)
  2 — Critical + Mid (21 tests)
  3 — All (24 tests)

  Reply with 1, 2, or 3.
  ```

  Reply with the number (or a word like "critical", "critical and mid", "all"/"everything"). The hook resolves your answer and test-execution is dispatched again, this time scoped to that level. If your reply doesn't match any option, you'll be asked again — nothing is guessed on your behalf.

Any test case excluded this way is **not** silently dropped — it shows up in the final report as `⏭ SKIPPED`, with the reason it was excluded (see Step 5 and Output Files below).

---

## Step 5 — Test Execution (including Design Comparison)

The `test-execution` agent works through every test case sequentially:

1. Reads `test-cases.md`, `test-data.md`, `vars.md`, and the spec file
2. **Captures** an `EXECUTION_STARTED` timestamp — since the agent has no `Bash`/`date` access, every timestamp is obtained by calling `mcp__playwright_headed__browser_evaluate` to read the clock inside the browser page
3. **Hydrates** each test case — replaces every `${field-name}` with the concrete value you filled in, and resolves every `<<view-id>>` / `{{BASE_URL}}` token into a real URL using the current `BASE_URL` from `vars.md`
4. **Filters** by the `EXECUTION_LEVEL` resolved in Step 4.5 — test cases whose `Severity` falls below the chosen level are marked `⏭ SKIPPED` and never run
5. For each remaining test case: navigates → snapshots DOM → fills inputs → clicks buttons → captures a timestamped screenshot — mandatory for **both** ✅ PASS and ❌ FAIL results (⚠️ BLOCKED cases never execute, so there's nothing to capture)
6. Classifies each result: **✅ PASS · ❌ FAIL · ⚠️ BLOCKED · ⏭ SKIPPED**
7. Captures an `EXECUTION_COMPLETED` timestamp and writes `Platform/Dashboard/test-report-dashboard.md`, including the execution level, the execution window (`EXECUTION_STARTED` – `EXECUTION_COMPLETED`), and a **Skipped Tests Details** section (if anything was skipped) in the report

### Design Comparison (TC-DC test cases)

If a `Pencil slide name / Figma frame URL` was provided in the spec's Screen Identification, the test generation step will have created a **TC-DC-01** test case. During execution, the agent:

1. Navigates to the page and takes a full screenshot
2. Retrieves the original design:
   - **Figma URL** → uses Figma MCP to fetch the frame's visual structure
   - **Pencil slide name** → uses Pencil MCP to locate and read the slide
3. Compares the live page against the design across 6 dimensions: structure/layout, typography, colors, spacing, components, and images/icons
4. Classifies each discrepancy by severity: **Critical · Major · Minor · Cosmetic**
5. Documents all findings in a dedicated **DESIGN COMPARISON** section of the report

The TC-DC test case passes only if zero critical or major discrepancies are found.

### Persistent Test Identity & Email Verification (Yopmail)

This procedure is defined once, in `skills/shared:account-identity/SKILL.md`, and followed identically by both `test-execution` (for signup/registration test cases) and `spec-wizard-generate` (for a page whose Auth answer is `new account` — see Step 1). Neither flow gets a fresh throwaway email every run:

1. If the relevant credential variable(s) in `vars.md` are still the placeholder values (or blank), the flow generates a persistent identity the first time it needs one: a random `qa-{random}@yopmail.com` address, plus a matching password if a password variable was specified.
2. It completes the signup with that identity. If the flow requires an OTP or a confirmation email, it opens a **second browser tab**, navigates to `https://yopmail.com/en/`, checks the inbox for that exact address, retrieves the code or clicks the confirmation link, then switches back to the original tab to continue — closing the Yopmail tab afterward.
3. If Yopmail ever shows a different inbox than expected, it returns to `https://yopmail.com/en/` and re-enters the correct address before continuing.
4. Only once account creation actually succeeds does it write the generated value(s) back into `vars.md` — every later run of either flow, and every other test case that needs to be logged in, reuses that same persisted identity via `{{AUTH_EMAIL}}` / `{{AUTH_PASSWORD}}`.
5. On later runs, since the account already exists: `test-execution` marks the signup test case itself `⚠️ BLOCKED` (not re-executed, to avoid a false failure from a duplicate-registration error), and `spec-wizard-generate` reuses the persisted identity to log in instead of signing up again. Restore the placeholders in `vars.md` if you want a brand-new account instead.

Any other test case whose steps require an OTP or confirmation-email check (password reset, 2FA, etc.) is verified the same way through Yopmail, regardless of whether it's tied to the persistent identity or a one-off email used earlier in that test case.

---

## Output Files Per Module

After the full pipeline, your module folder contains:

```
Platform/Dashboard/
├── dashboard-description.md        ← spec (created by spec-wizard-generate)
├── dashboard-analysis.png          ← screenshot from auto-generation analysis
├── test-cases.md                   ← generated test cases
├── test-data.md                    ← filled test data
├── test-report-dashboard.md        ← execution report (includes execution level, skipped tests, execution window)
└── TC-*.png                        ← timestamped screenshot evidence per test (e.g. TC-SMK-01-page-loaded-20260703-143205.png)
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

### Execute tests at a specific roughness level (skips the question)

```
Invoke: qa-coordinator
"Execute tests for Platform/Login/login-description.md, critical and mid only"
```

---

## Quick Reference

| You want to… | Agent | Message / Action |
|---|---|---|
| Auto-generate a spec from a live page | `spec-wizard-generate` | `"Create a spec for /dashboard, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD"` |
| Auto-generate a spec behind a brand-new account | `spec-wizard-generate` | `"Create a spec for /account/settings, new account at /signup with email: AUTH_EMAIL, password: AUTH_PASSWORD, destination /account/settings"` |
| Auto-generate with design comparison | `spec-wizard-generate` | `"Create a spec for /dashboard, design reference: https://figma.com/design/...?node-id=..."` |
| Auto-generate with Pencil design | `spec-wizard-generate` | `"Create a spec for /login, design reference: Login Screen"` |
| Enrich spec with requirements from a file | `spec-wizard-generate` | At the enrichment prompt, type a file path (e.g. `/docs/requirements.md`) |
| Enrich spec with requirements from docs/ folder | `spec-wizard-generate` | At the enrichment prompt, type `docs` |
| Skip requirements enrichment | `spec-wizard-generate` | At the enrichment prompt, type `skip` |
| Improve an existing spec interactively | `spec-wizard-improve` | `"Improve Platform/Dashboard/dashboard-description.md"` |
| See spec summary + offer pipeline | `spec-wizard-pipeline` | `"Summarize Platform/Dashboard/dashboard-description.md"` |
| Full pipeline on an existing spec | `qa-coordinator` | `"Run the full QA pipeline for Platform/Dashboard/dashboard-description.md"` |
| Generate test cases only | `qa-coordinator` | `"Generate test cases only for Platform/Dashboard/dashboard-description.md"` |
| Execute already-filled tests | `qa-coordinator` | `"Execute tests for Platform/Dashboard/dashboard-description.md"` |
| Execute only the critical tests | `qa-coordinator` | `"Execute tests for Platform/Dashboard/dashboard-description.md, just the critical tests"` |
| Create spec without login | `spec-wizard-generate` | `"Create a spec for /jobs, module name vacantes"` |

---

## Tips

- **Plugin updates** — keep the plugin current with `claude plugin update AI-Driven-UI-Specification`. This pulls the latest agents, skills, and hooks without touching your `Platform/` output files or `vars.md`.

- **All output goes to `Platform/`** — every module gets its own subfolder. This keeps specs, test cases, and reports organized by screen.

- **Requirements enrichment** — place your project requirements or user stories as `.md` or `.csv` files in a `docs/` folder at your project root. When the agent asks about requirements enrichment, type `docs` to apply them automatically. The agent matches requirements to the specific view being analyzed — it only applies relevant items and ignores content for other modules.

- **Design comparison** — provide a Figma frame URL or Pencil slide name when creating a spec to enable automatic design-vs-implementation comparison. The system retrieves the design using the appropriate MCP tool and compares it against the live page during test execution. Discrepancies are classified by severity and documented in the report.

- **Headed mode only** — the system always uses the headed Playwright browser. You can watch the browser during execution, which is useful when debugging failures.

- **Re-running after a fix** — invoke `qa-coordinator` with "Execute tests for …" (execute-only mode). No need to regenerate test cases unless the spec changed.

- **Updating the spec** — run `spec-wizard-improve` on the existing file. Then re-run `qa-coordinator` to regenerate test cases from the updated spec.

- **Multiple modules** — each module lives in its own `Platform/{ModuleName}/` folder. Run the pipeline on any of them independently.

- **Changing the base URL** — edit `vars.md`. `test-cases.md` and `test-data.md` never need to be regenerated: they reference navigation symbolically (`<<view-id>>` / `{{BASE_URL}}`), and only `test-execution` resolves `BASE_URL` into a real URL, at run time.

- **Execution timestamps** — the `test-execution` agent has no `Bash`/`date` access, so it reads the clock via a Playwright `browser_evaluate` call. Every report includes an `EXECUTION_STARTED` / `EXECUTION_COMPLETED` execution window, and every screenshot filename carries its own capture timestamp.

- **Execution roughness gate** — if your Claude Code session isn't in **auto** permission mode, the pipeline asks how thorough a run should be (Critical only / Critical + Mid / All) before test-execution starts, using each test case's `Severity`. State the level upfront in your request (e.g. "just the critical tests") to skip the question — this works the same whether or not auto mode is on. In auto mode with no level stated, it defaults to running everything. Anything excluded shows up in the report as `⏭ SKIPPED`, never silently dropped.

- **Credentials management** — store all login credentials in `vars.md` as named variables. When invoking agents, reference them by variable name only. This keeps sensitive data out of chat history.

- **Pipeline state** — the `.claude/.pipeline-state` file tracks where you are in the pipeline. If something gets stuck, delete this file to reset state and start fresh.

- **No programmatic Playwright** — the system never writes or runs Playwright code. All browser automation happens through MCP tool calls. No `node_modules`, no test scripts, no `npx playwright` commands.

- **Understanding the system** — for a deep-dive into how agents, skills, and hooks work together, read [personal-explanation.md](personal-explanation.md).
