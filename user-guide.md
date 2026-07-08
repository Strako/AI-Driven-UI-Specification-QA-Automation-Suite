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
│  Step 0          Step 1          Step 1.5       Step 2          Step 3      │
│                                                                             │
│  qa-coord     → spec-wizard  → docs/       → spec-wizard  → qa-coord       │
│  (entry point)  -generate      enrichment    -improve       + test-exec    │
│  (automated)    (automated)    (automatic,   (you + AI,     (automated)    │
│       │              │          silent)       optional)         │         │
│  bootstraps    spec in        refined spec   saved spec    test-cases      │
│  the spec      memory         in memory      on disk,      test-data      │
│  request                      [only if       reports        test-report   │
│                                docs/ exists]  straight       screenshots   │
│                                               back to        [YOU FILL     │
│                                               qa-coord]       test-data]   │
└─────────────────────────────────────────────────────────────────────────────┘
```

> `qa-coordinator` is always the entry point — even for a bare "create a spec for X" with no mention of testing. A `PreToolUse` hook (`pipeline-on-spec-dispatch.sh`) enforces this: any direct dispatch of `spec-wizard-generate` is blocked and redirected to `qa-coordinator`, which then bootstraps the spec itself (Step 0). **There is no "just create the spec and stop" outcome once you reach `qa-coordinator` this way** — the only question anywhere in this flow is whether to pause once for the improvement wizard (end of Step 1); the pipeline always runs through to a delivered report afterward. The only way to get a narrower result (just a spec, or a spec review with a real yes/no on whether to run the pipeline) is to explicitly invoke an individual agent by name instead — see **Running the Pipeline Manually** below.
>
> Every question in this pipeline — the improvement-wizard offer (end of Step 1), the pause to fill `test-data.md`, and the **Execution Roughness Gate** — is enforced by a `PreToolUse` hook, not just an instruction the agent might skip or forget. These hooks do **not** all treat Claude Code's **auto** permission mode the same way:
>
> - The **docs/ enrichment step (Step 1.5)** never asks a question at all, in any mode — it's a pure filesystem check (does `docs/` exist and have readable files?), not a permission-mode decision.
> - The **improvement-wizard offer** and **execution roughness gate** are both skipped automatically in auto mode, each defaulting to the "keep going" answer (skip the wizard, run all tests).
> - The **test-data-fill pause** is the one exception: it is **never** skipped by auto mode alone. It only skips if your initial request explicitly asked for automatic test data generation (see **Step 3.5**) — auto mode by itself always still pauses here, because running tests against unconfirmed data is exactly what this gate exists to prevent.
>
> In practice this means a single **"create a spec for X"** request in auto mode runs unattended through spec creation, enrichment, the wizard offer, and test generation — but still pauses for you to fill `test-data.md` unless you also explicitly asked for automatic test data. Add that to the same request for a fully unattended run end-to-end. The roughness question is also skipped (in either mode) if you already stated a level upfront.

---

## Step 1 — Auto-Generate the Spec

The auto-generator navigates to your live page using Playwright MCP, analyzes the full DOM (scrolling, tabs, expandable sections), and produces a complete spec file in one pass.

### Invoke the agent

In Claude Code, describe what you need — you don't need to name any agent explicitly; `qa-coordinator` is the entry point for this request and bootstraps the spec itself via `spec-wizard-generate` (Step 0). A direct dispatch of `spec-wizard-generate` is redirected to `qa-coordinator` automatically if you (or the model) try it anyway. You can front-load all inputs in one message:

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
8. **Attempts to save** — a hook silently checks for a `docs/` folder and applies it if present (see Step 1.5 below); no question is ever asked here
9. **Saves** the enriched spec to `Platform/{ModuleName}/{module}-description.md`

Then prints:

```
✅  Spec saved: Platform/Dashboard/dashboard-description.md
```

Control now returns to `qa-coordinator` — `spec-wizard-generate` itself never asks anything else and never dispatches another agent. `qa-coordinator` immediately attempts to move into test generation, and it's *that* attempt which is gated on the improvement-wizard question:

```
The spec for dashboard has been generated.
Would you like to run the improvement wizard to review and refine each section interactively before continuing into the QA pipeline?
- yes → opens the spec improvement wizard, then continues into the pipeline
- no → continues straight into the QA pipeline
```

> **If your Claude Code session is in auto permission mode**, a `PreToolUse` hook (`pipeline-on-spec-dispatch.sh`) skips this question automatically — `qa-coordinator` never asks anything itself first, it just attempts to move straight into test generation, as if you'd already answered "no." You will not see this prompt at all in auto mode. **There is no separate "run the QA pipeline?" question anywhere in this flow** — reaching `qa-coordinator` at all already means the full pipeline runs through to a report; the only thing this question decides is whether to pause once for the wizard first.

---

## Step 1.5 — Automatic docs/ Enrichment

Before writing the spec to disk for the first time, a `PreToolUse` hook (`pipeline-on-spec-write-gate.sh`) checks whether a `docs/` folder exists at your project root with at least one readable requirements file. **This is not a question asked of you** — nothing is ever printed and nothing waits for a reply, in any mode. It's a deterministic filesystem check, not a permission-mode decision.

- **If `docs/` doesn't exist, or has nothing readable in it** — the spec saves immediately. Nothing to see here.
- **If `docs/` has `.md` or `.csv` files** — the save is blocked exactly once so the agent can read them, apply anything relevant, and retry:

```
docs/
├── requirements.md          ← scanned automatically
├── user-stories.md          ← scanned automatically
└── acceptance-criteria.csv  ← scanned automatically
```

> The agent locates "project root" by finding `vars.md` via a Glob search — so your `docs/` folder just needs to sit next to `vars.md`. `.xlsx` files are skipped as unreadable (re-export as `.md` or `.csv` if you want a spreadsheet's content applied).

The agent identifies requirements **relevant to this specific view** (matched by module name, route, component names, or feature keywords) and applies them to the in-memory spec before retrying the save:

- Adds missing fields mentioned in requirements
- Adds business rules derived from acceptance criteria
- Adds screen states and actions described in user stories
- Expands the Detailed Flow Description with requirement-driven scenarios

After enrichment, the agent prints a summary and retries the save:

```
✅  Requirements enrichment applied from docs/

  Files scanned   : requirements.md, acceptance-criteria.csv
  Relevant items  : 7 requirements matched to dashboard
  Changes applied :
    • Added field ${dashboard-active-jobs-count} to Stats Panel component
    • Added business rule: Only admin users may access this view
    • Added screen state: empty (no active jobs)
```

If you don't keep a `docs/` folder, or this particular run has nothing relevant to add, you can still refine the spec manually in Step 2 (the improvement wizard) or by editing the file directly — there's no other way to feed in requirements for a direct spec-creation request.

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

After all 9 sections, the wizard shows the complete updated spec and asks for confirmation. Once saved, it reports back to `qa-coordinator` directly — there's no further question, `qa-coordinator` immediately continues into test generation (Step 3 below).

> This step is reached two different ways, and they behave slightly differently after saving: coming from **Step 1** (the default flow, `qa-coordinator` dispatched the wizard for you), the wizard reports straight back to `qa-coordinator` and the full pipeline continues unconditionally. If you instead invoked `spec-wizard-improve` **standalone**, by name, on an already-existing spec (not through Step 1 at all), it keeps its original behavior: it launches `spec-wizard-pipeline`, which shows a spec summary and asks a real "run the QA pipeline? yes/no" question — since that's a deliberate, individual tool invocation rather than the default entry point.

---

## Step 3 — Test Generation

Whether you came from the improvement wizard or skipped it, `qa-coordinator` attempts to dispatch `test-generation` immediately — there's no summary shown and no "run the pipeline?" question here; reaching `qa-coordinator` at all already means the full pipeline runs through to a report.

### What `test-generation` produces

The agent reads your spec (and any related spec files), then writes two files:

**`test-cases.md`** — complete, data-agnostic test cases

Every interactive element is referenced as `${field-name}` and every navigation as `<<view-id>>` / `{{BASE_URL}}` — never a hardcoded value or domain. `test-generation` never reads `vars.md`; `BASE_URL` is only resolved later, by `test-execution`, so the same test cases run against any environment without regeneration.

Coverage generated: **Happy Path · Smoke · Functional · Edge Cases · Exploratory**

Every test case is also assigned a **Severity** — Critical, Mid, or Low — judged by business impact (the happy path and smoke checks are typically Critical; edge cases and exploratory scenarios are typically Low). This severity is what Step 4.5 uses to scope how much of the suite actually runs.

**`test-data.md`** — organized by scenario, empty by default:

```markdown
# Test Data — <<dashboard-3f2c1a9b-...>>

## [TC-HP-01] Job search works correctly

### <<dashboard-3f2c1a9b-...>>

- ${jobs-search}:
- ${jobs-status-filter}:
```

Unless you explicitly asked for automatic test data generation in your initial request (see **Step 3.5** below), every field stays blank like this for you to fill in manually.

After both files are written, the coordinator reports Stage 1 completion and immediately attempts to dispatch test execution:

```
✅ Stage 1 complete — Test cases generated.

  test-cases.md  → 24 cases (Smoke: 3, HP: 2, Functional: 9, Edge: 6, Exploratory: 4)
                   Severity: 6 Critical, 15 Mid, 3 Low
  test-data     → 14 scenarios
```

A `PreToolUse` hook blocks that dispatch attempt until you confirm the test data is filled in, and the coordinator pauses:

```
Before execution, fill in the test data:
📄 Platform/Dashboard/test-data.md

Reply here when you are ready to continue.
```

**This pause happens regardless of Claude Code's permission mode** — unlike every other pause in this pipeline, auto mode does **not** skip it. The only way to skip it is Step 3.5 below.

---

## Step 3.5 — Automatic Test Data Generation (optional)

If you'd rather not fill `test-data.md` by hand — for a fully unattended run, or just to save time — say so in your **initial** request, e.g.:

```
Create a spec for /dashboard and run the full QA pipeline, generate the test data automatically.
```

`qa-coordinator` parses this at Startup and passes `AUTO_FILL_TEST_DATA: true` to `test-generation`, which fills every field itself instead of leaving it blank:

- **Credential-like fields** tied to a named `vars.md` variable (e.g. a login field referencing `{{AUTH_EMAIL}}`) get the real value from `vars.md` if one is already set; otherwise they're left blank rather than inventing a credential that won't match your app.
- **Signup/registration fields** are always left blank regardless — `test-execution` generates and confirms a fresh Yopmail identity for those itself, and this must stay the single source of truth for that account.
- **Every other field** gets a plausible, obviously-a-test-value based on its name, type, and any validation rules in the spec (e.g. a well-formed email, a number inside a stated range, one of a dropdown's documented options).

With `test-data.md` already filled, `qa-coordinator` includes `AUTO_TEST_DATA: true` on the test-execution dispatch, and the Step 4 pause below is skipped entirely — you go straight to Step 4.5 / Step 5. Always skim the auto-filled `test-data.md` before a real run if the values matter to you; nothing stops you from editing it further before test execution actually starts (the file is already fully written by this point, and the pause is only skipped, not the file's existence — you could interrupt after Stage 1 and edit it if truly needed).

---

## Step 4 — Fill `test-data.md`

> Skip this step if you used **Step 3.5** — `test-data.md` is already filled and the pause never happened.

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

Before test-execution actually starts, the same hook that gated the test-data confirmation in Step 3/3.5 checks a second, independent gate — this one **is** affected by whether your Claude Code session is running in **auto** permission mode (unlike the test-data gate before it).

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
2. **Captures** an `EXECUTION_STARTED` timestamp — since the agent has no `Bash`/`date` access, every timestamp is obtained by calling `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate` to read the clock inside the browser page
3. **Hydrates** each test case — replaces every `${field-name}` with the concrete value you filled in, and resolves every `<<view-id>>` / `{{BASE_URL}}` token into a real URL using the current `BASE_URL` from `vars.md`
4. **Filters** by the `EXECUTION_LEVEL` resolved in Step 4.5 — test cases whose `Severity` falls below the chosen level are marked `⏭ SKIPPED` and never run
5. For each remaining test case: navigates → snapshots DOM → fills inputs → clicks buttons → captures a timestamped screenshot into the module's `evidences/` subfolder — mandatory for **both** ✅ PASS and ❌ FAIL results (⚠️ BLOCKED cases never execute, so there's nothing to capture)
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
└── evidences/                      ← created automatically when test-cases.md is generated
    └── TC-*.png                    ← timestamped screenshot evidence per test (e.g. TC-SMK-01-page-loaded-20260703-143205.png)
```

---

## Running the Pipeline Manually

You don't have to go through the full flow every time. Here's how to invoke each stage independently:

### Create a spec (auto-generate only)

```
Invoke: qa-coordinator
"Create a spec for /jobs, module name vacantes"
```

> `qa-coordinator` is always the entry point here — a direct dispatch of `spec-wizard-generate` gets redirected to it automatically.

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
| Auto-generate a spec from a live page | `qa-coordinator` | `"Create a spec for /dashboard, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD"` |
| Auto-generate a spec behind a brand-new account | `qa-coordinator` | `"Create a spec for /account/settings, new account at /signup with email: AUTH_EMAIL, password: AUTH_PASSWORD, destination /account/settings"` |
| Auto-generate with design comparison | `qa-coordinator` | `"Create a spec for /dashboard, design reference: https://figma.com/design/...?node-id=..."` |
| Auto-generate with Pencil design | `qa-coordinator` | `"Create a spec for /login, design reference: Login Screen"` |
| Enrich spec with requirements automatically | (automatic) | Place `.md`/`.csv` files in a `docs/` folder at the project root — applied silently, no action needed |
| Improve an existing spec interactively | `spec-wizard-improve` | `"Improve Platform/Dashboard/dashboard-description.md"` |
| See spec summary + offer pipeline | `spec-wizard-pipeline` | `"Summarize Platform/Dashboard/dashboard-description.md"` |
| Full pipeline on an existing spec | `qa-coordinator` | `"Run the full QA pipeline for Platform/Dashboard/dashboard-description.md"` |
| Generate test cases only | `qa-coordinator` | `"Generate test cases only for Platform/Dashboard/dashboard-description.md"` |
| Generate test cases with test data auto-filled | `qa-coordinator` | `"Generate test cases for Platform/Dashboard/dashboard-description.md, generate the test data automatically"` |
| Execute already-filled tests | `qa-coordinator` | `"Execute tests for Platform/Dashboard/dashboard-description.md"` |
| Execute only the critical tests | `qa-coordinator` | `"Execute tests for Platform/Dashboard/dashboard-description.md, just the critical tests"` |
| Run the full pipeline fully unattended | `qa-coordinator` | `"Create a spec for /jobs and run the full QA pipeline, generate the test data automatically"` (in auto permission mode) |
| Create spec without login | `qa-coordinator` | `"Create a spec for /jobs, module name vacantes"` |

---

## Tips

- **Plugin updates** — keep the plugin current with `claude plugin update AI-Driven-UI-Specification`. This pulls the latest agents, skills, and hooks without touching your `Platform/` output files or `vars.md`.

- **All output goes to `Platform/`** — every module gets its own subfolder. This keeps specs, test cases, and reports organized by screen.

- **Screenshot evidence lives in `evidences/`** — every `TC-*.png` from test execution is saved inside `Platform/{ModuleName}/evidences/`, never directly in the module folder. This subfolder is created automatically by a pipeline hook the moment `test-cases.md` is generated, so it's already there by the time execution starts. (The `{module}-analysis.png` from spec auto-generation is unrelated and stays in the module root.)

- **Requirements enrichment** — place your project requirements or user stories as `.md` or `.csv` files in a `docs/` folder at your project root. There's nothing to type or confirm — a `PreToolUse` hook checks for `docs/` before every first-time spec save and applies anything relevant automatically, silently, in every mode. The agent matches requirements to the specific view being analyzed — it only applies relevant items and ignores content for other modules.

- **Design comparison** — provide a Figma frame URL or Pencil slide name when creating a spec to enable automatic design-vs-implementation comparison. The system retrieves the design using the appropriate MCP tool and compares it against the live page during test execution. Discrepancies are classified by severity and documented in the report.

- **Headed mode only** — the system always uses the headed Playwright browser. You can watch the browser during execution, which is useful when debugging failures.

- **Re-running after a fix** — invoke `qa-coordinator` with "Execute tests for …" (execute-only mode). No need to regenerate test cases unless the spec changed.

- **Updating the spec** — run `spec-wizard-improve` on the existing file. Then re-run `qa-coordinator` to regenerate test cases from the updated spec.

- **Multiple modules** — each module lives in its own `Platform/{ModuleName}/` folder. Run the pipeline on any of them independently.

- **Changing the base URL** — edit `vars.md`. `test-cases.md` and `test-data.md` never need to be regenerated: they reference navigation symbolically (`<<view-id>>` / `{{BASE_URL}}`), and only `test-execution` resolves `BASE_URL` into a real URL, at run time.

- **Execution timestamps** — the `test-execution` agent has no `Bash`/`date` access, so it reads the clock via a Playwright `browser_evaluate` call. Every report includes an `EXECUTION_STARTED` / `EXECUTION_COMPLETED` execution window, and every screenshot filename carries its own capture timestamp.

- **Test data confirmation gate** — a `PreToolUse` hook blocks test-execution from starting until you've explicitly confirmed `test-data.md` is filled in (see Step 3/4). Unlike every other gate in this pipeline, Claude Code's **auto** permission mode does **not** skip this one — it only skips if you explicitly asked for automatic test data generation in your initial request (Step 3.5). Running an unattended session in auto mode without that request still pauses here.

- **Execution roughness gate** — if your Claude Code session isn't in **auto** permission mode, the pipeline asks how thorough a run should be (Critical only / Critical + Mid / All) before test-execution starts, using each test case's `Severity`. State the level upfront in your request (e.g. "just the critical tests") to skip the question — this works the same whether or not auto mode is on. In auto mode with no level stated, it defaults to running everything. Anything excluded shows up in the report as `⏭ SKIPPED`, never silently dropped.

- **Credentials management** — store all login credentials in `vars.md` as named variables. When invoking agents, reference them by variable name only. This keeps sensitive data out of chat history.

- **Pipeline state** — the `.claude/.pipeline-state` file tracks where you are in the pipeline. If something gets stuck, delete this file to reset state and start fresh.

- **No programmatic Playwright** — the system never writes or runs Playwright code. All browser automation happens through MCP tool calls. No `node_modules`, no test scripts, no `npx playwright` commands.

- **Understanding the system** — for a deep-dive into how agents, skills, and hooks work together, read [personal-explanation.md](personal-explanation.md).
