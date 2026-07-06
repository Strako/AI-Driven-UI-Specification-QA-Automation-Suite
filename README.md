# AI-Driven-UI-Specification — QA Automation Suite

A Claude-native agent system for end-to-end UI test automation. From a live page URL to a full test execution report — with automatic spec generation, interactive improvement, and browser-driven test execution.

> **New here?** Read the [User Guide](user-guide.md) or the [Docs](https://docs-ai-driven-ui-specs.netlify.app) for a complete step-by-step walkthrough.

---

## Install as a Claude Code Plugin

Install via the Claude Code plugin system. Agents, skills, and hooks always run directly from the installed plugin — they are never copied into your project's `.claude/` directory.

### Prerequisites

| Dependency | Minimum Version | Purpose |
|---|---|---|
| [Node.js](https://nodejs.org/) | v18+ | Runtime for `npx` and Playwright MCP server |
| [npm](https://www.npmjs.com/) | v9+ | Package manager (ships with Node.js) |
| [Python 3](https://www.python.org/) | v3.8+ | Used by pipeline hooks for JSON parsing |
| [Google Chrome](https://www.google.com/chrome/) | Latest stable | Browser used by Playwright MCP in headed mode |
| [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | Latest | Agent runtime that executes the multi-agent system |

**System requirements:** macOS, Linux, or Windows (WSL recommended) · 4 GB RAM minimum · ~500 MB disk

**Step 1 — Add this repository as a plugin marketplace (one-time per machine):**

```bash
claude plugin marketplace add Strako/AI-Driven-UI-Specification-QA-Automation-Suite
```

**Step 2 — Install the plugin into your project:**

```bash
claude plugin install AI-Driven-UI-Specification
```

This registers the plugin's agents, skills, hooks, and MCP servers with Claude Code. They are loaded straight from the plugin's installed location (`${CLAUDE_PLUGIN_ROOT}`) at runtime — nothing is copied into your project.

**Step 3 — Set up your project.** These are project-specific files you create yourself (not plugin files, so there's nothing to copy from the plugin for these):

```bash
# 1. Create vars.md at your project root with your app's base URL and credentials
cat > vars.md <<'EOF'
BASE_URL = https://your-app.example.com
AUTH_EMAIL = admin@your-app.example.com
AUTH_PASSWORD = your-password
EOF

# 2. Create the output directory
mkdir -p Platform

# 3. (Optional) Create the requirements folder
#    Place .xlsx, .csv, or .md requirement files here — the spec generator
#    will scan this folder automatically when you type "docs" at the enrichment prompt
mkdir -p docs

# 4. (Optional) Set Figma token if you plan to use design comparison
echo 'export FIGMA_ACCESS_TOKEN=fig_xxxxxxxxxxxxx' >> ~/.zshrc && source ~/.zshrc
```

Open Claude Code — all agents, skills, and hooks are ready.

> **For contributors modifying this plugin's source:** clone the repo, edit files under `agents/`, `skills/`, `hooks/`, then reinstall/reload the plugin so Claude Code picks up the change from the plugin's own directory. Do not copy these files into a separate project's `.claude/` folder — that creates a stale, disconnected fork of the plugin logic.

---

## How It Works

The system uses seven Claude agents organized into three stages: spec creation, test generation, and test execution. A pipeline state machine and shell hooks coordinate transitions between stages automatically.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                            FULL PIPELINE                                   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  SPEC CREATION (3 agents)                                           │   │
│  │                                                                     │   │
│  │  spec-wizard-generate                                               │   │
│  │       │                                                             │   │
│  │       ├── 1. Playwright analysis (DOM + screenshots)                │   │
│  │       ├── 2. Auto-generate spec in memory                           │   │
│  │       ├── 3. [optional] Requirements enrichment                     │   │
│  │       │        └── from file path (.md/.csv/.xlsx) or docs/ folder  │   │
│  │       └── 4. Save {module}-description.md                           │   │
│  │              │                                                      │   │
│  │              ├── yes ──► spec-wizard-improve (section refinement)   │   │
│  │              │                    │                                 │   │
│  │              └── no ─────────────┼──► spec-wizard-pipeline          │   │
│  │                                  └──► spec-wizard-pipeline          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                       │
│                              yes to pipeline                               │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  QA PIPELINE (qa-coordinator + 2 agents)                            │   │
│  │                                                                     │   │
│  │  qa-coordinator                                                     │   │
│  │       │                                                             │   │
│  │       ├── test-generation ──► test-cases.md + test-data.md          │   │
│  │       │                                                             │   │
│  │       │   [PAUSE — user fills test-data.md]                         │   │
│  │       │                                                             │   │
│  │       └── test-execution ──► test-report-{module}.md + screenshots  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

This repository **is** the Claude Code plugin. Its root is the plugin root — when a user runs `claude plugin install`, Claude Code registers `.claude-plugin/plugin.json` and loads the plugin's agents, skills, and hooks directly from this installed location at runtime, addressed via `${CLAUDE_PLUGIN_ROOT}`. Nothing here is copied into the consuming project's `.claude/` directory.

```
.                                    ← repository root = plugin root
├── .claude-plugin/
│   ├── plugin.json                  Claude Code plugin manifest (name, version, file map)
│   └── marketplace.json             Marketplace catalog (lets users add this repo as a source)
├── package.json                     npm package metadata
├── settings.json                    plugin-level permissions + hooks (references ${CLAUDE_PLUGIN_ROOT})
├── .mcp.json                        bundled MCP server config (playwright_headed, figma)
│
├── agents/                          loaded directly by Claude Code as plugin agents
│   ├── spec-wizard.md               Legacy entry point (delegates to spec-wizard-generate)
│   ├── spec-wizard-generate.md      Auto-generates spec from live page via Playwright
│   ├── spec-wizard-improve.md       Interactive section-by-section spec refinement
│   ├── spec-wizard-pipeline.md      Shows spec summary and offers QA pipeline
│   ├── qa-coordinator.md            Pipeline orchestrator (dispatches gen + exec)
│   ├── test-generation.md           Test case generator from spec
│   └── test-execution.md            Browser test executor via Playwright MCP
│
├── skills/                          read by agents at runtime via ${CLAUDE_PLUGIN_ROOT}/skills/...
│   ├── spec-wizard:auto-generate/
│   │   └── SKILL.md                 Navigate → analyze → generate spec → enrich → save
│   ├── spec-wizard:improve/
│   │   └── SKILL.md                 9-section interactive improvement wizard
│   ├── spec-wizard:pipeline-offer/
│   │   └── SKILL.md                 Summarize spec → offer QA pipeline
│   ├── test-generation:process/
│   │   └── SKILL.md                 6-step test case generation
│   ├── test-execution:process/
│   │   └── SKILL.md                 6-step browser test execution + design comparison
│   └── shared:account-identity/
│       └── SKILL.md                 Shared: generate/persist a Yopmail test identity + OTP verification (used by spec-wizard-generate and test-execution)
│
├── hooks/                           executed in place via ${CLAUDE_PLUGIN_ROOT}/hooks/...
│   ├── pipeline-on-user-prompt.sh   Routes user responses to next pipeline stage
│   ├── pipeline-on-spec-created.sh  Detects spec file writes → updates state
│   ├── pipeline-on-tests-generated.sh  Detects test-cases.md writes → updates state
│   ├── pipeline-on-report-written.sh   Detects report writes → marks complete
│   └── pipeline-on-execution-dispatch.sh  Gates the test-execution dispatch on auto mode
│
├── TEMPLATE.md                      Canonical spec format — referenced from your project root; create your own copy there
├── vars.md                          Example credentials file — create your own copy at your project root
├── README.md                        This file
├── user-guide.md                    Step-by-step walkthrough
├── personal-explanation.md          Deep-dive into agents, skills, and hooks
└── INSTALL.md                       Detailed installation and setup guide
```

### After Plugin Installation — What Lands in Your Project

```
YOUR_PROJECT/
├── .claude/
│   ├── agents/                      7 agent definition files
│   ├── skills/                      6 skill directories with SKILL.md files
│   ├── hooks/                       5 pipeline hook scripts (executable)
│   ├── settings.json                permissions + hook event configuration
│   └── .pipeline-state              pipeline progress tracker (auto-managed)
│
├── .mcp.json                        playwright_headed + figma MCP server config
│
├── Platform/                        ← create this: mkdir Platform
│   └── {ModuleName}/                one folder per UI screen (auto-created by agents)
│       ├── {module}-description.md  UI screen spec
│       ├── {module}-analysis.png    screenshot from analysis
│       ├── test-cases.md            generated test cases (data-agnostic)
│       ├── test-data.md             fillable test data template
│       ├── test-report-{module}.md  execution report
│       └── TC-*.png                 timestamped screenshot evidence per test
│
├── docs/                            ← create this for requirements enrichment
│   └── *.md / *.csv                requirements files scanned during spec generation
│
├── TEMPLATE.md                      canonical spec format (read by all agents)
├── vars.md                          BASE_URL + credentials (fill in your values)
└── user-guide.md                    step-by-step usage walkthrough
```

---

## Agents

### `spec-wizard-generate` — Auto Spec Generator

> **Model:** Opus · **Skill:** `spec-wizard:auto-generate` · **MCP:** `playwright_headed`

Navigates to a live page with Playwright MCP, analyzes the full DOM (including scrolling, tabs, and expandable sections), and produces a complete `{module}-description.md` spec file in one pass — no interactive interview required.

Before writing the spec to disk, optionally enriches it with project requirements:

- **File path** → reads the provided `.md`, `.csv`, or `.xlsx` file, extracts requirements relevant to this view, and refines the spec in memory
- **`docs`** → auto-scans the `docs/` folder at the project root for requirement files and applies relevant ones. The agent derives the project root by locating `vars.md` via Glob — so "project root" always means the folder that contains your `vars.md`. If `docs/` does not exist or is empty, the agent prints a warning and saves the spec as generated without failing.
- **`skip`** → saves the spec as generated without enrichment

After saving, offers two paths:

- **Yes** → launches `spec-wizard-improve` for interactive section-by-section refinement
- **No** → launches `spec-wizard-pipeline` to offer the QA pipeline

| Input | Required | Description |
|---|---|---|
| `PAGE_URL` | Yes | Full URL or path to analyze |
| `MODULE_NAME` | No | Kebab-case name (derived from URL if omitted) |
| `AUTH_REQUIRED` | No | Whether the page needs an authenticated session first |
| `AUTH_MODE` | If auth | `existing` (default) — log in with an account already in `vars.md`. `new` — create a fresh account first via Yopmail (see below). |
| `LOGIN_ROUTE` | If `existing` | Route or URL of the login page |
| `SIGNUP_ROUTE` | If `new` | Route or URL of the signup/registration page |
| `AUTH_EMAIL_VAR` | If auth | Variable name in `vars.md` for the email/username (e.g. `AUTH_EMAIL`). Credentials are never hardcoded — always read from (and for `new`, written to) `vars.md`. |
| `AUTH_PASSWORD_VAR` | If auth | Variable name in `vars.md` for the password (e.g. `AUTH_PASSWORD`). Omit for `AUTH_MODE=new` passwordless signups. Credentials are never hardcoded. |
| `DESTINATION_ROUTE` | If auth | Page to analyze after login or account creation |
| `OUTPUT_DIR` | No | Output directory (default: `Platform/{ModuleName}/`) |
| `DESIGN_REFERENCE` | No | Pencil slide name or Figma frame URL for design comparison. Populates the "Pencil slide name / Figma frame URL" field in Screen Identification. |

**Account creation (`AUTH_MODE=new`).** If the named `vars.md` variables are still placeholders (or blank), this agent generates a fresh `qa-{random}@yopmail.com` test identity, submits the signup form with it, confirms any OTP/confirmation link via a second-tab Yopmail check, and persists the result to `vars.md` — the same shared procedure (`${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md`) that `test-execution` uses. If a real identity is already persisted there, it's reused instead of signing up again.

**Output:** `Platform/{ModuleName}/{module}-description.md`

---

### `spec-wizard-improve` — Interactive Spec Refinement

> **Model:** Opus · **Skill:** `spec-wizard:improve`

Takes an existing spec file and walks through all 9 content sections in order. For each section it shows the current content, asks targeted questions, applies changes, and waits for explicit confirmation before advancing.

After saving, automatically invokes `spec-wizard-pipeline`.

| Input | Required | Description |
|---|---|---|
| `SPEC_FILE` | Yes | Path to the existing spec `.md` file |
| `PROJECT_ROOT` | No | Project root path (auto-detected if omitted) |

**Sections reviewed (in order):** Screen Identification · Origin Context · Components (one at a time) · View-Level Fields · Screen States · Related Views · Business Rules · Actions and Transitions · Detailed Flow Description

---

### `spec-wizard-pipeline` — Pipeline Offer

> **Model:** Opus · **Skill:** `spec-wizard:pipeline-offer`

Reads a completed spec file, shows a structured summary (components, fields, states, rules, actions), and offers to launch the full QA pipeline via `qa-coordinator`.

| Input | Required | Description |
|---|---|---|
| `SPEC_FILE` | Yes | Path to the completed spec file |
| `PROJECT_ROOT` | No | Project root path (auto-detected if omitted) |

---

### `qa-coordinator` — Pipeline Orchestrator

> **Model:** Opus · **Dispatches:** `test-generation`, `test-execution`

Collects a spec file path, then runs the full pipeline or individual stages. Always uses headed browser mode. Pauses between generation and execution for the user to fill `test-data.md`. After execution, the final summary includes the results breakdown plus an **execution window** (`{STARTED} – {COMPLETED}`) taken from the test-execution report timestamps.

| Mode | Trigger |
|---|---|
| **Full Pipeline** (default) | No specific stage mentioned |
| **Generate Only** | "generate", "test cases only", "create tests" |
| **Execute Only** | "execute", "run tests", "only execute" |

**Execution Roughness Gate** — before dispatching `test-execution`, a `PreToolUse` hook checks whether the session is running in Claude Code's **auto** permission mode:

- If the initiating message already states a level explicitly (e.g. "just run the critical tests"), that always wins — no question is asked, in either mode.
- Otherwise, in **auto** mode, execution defaults to running **all** test cases (level 3) — nobody is necessarily watching to answer a question.
- Otherwise (not auto mode, no explicit level), the hook blocks the dispatch and `qa-coordinator` asks the user directly:

  > **1** — Critical only · **2** — Critical + Mid · **3** — All

  using the Critical/Mid/Low counts from test-generation's `SEVERITY_BREAKDOWN`. Once answered, the dispatch retries with `EXECUTION_LEVEL` set.

**Pipeline flow:**

```
spec file → test-generation → test-cases.md + test-data.md
                                    │
                              [PAUSE — fill test-data.md]
                                    │
                              test-execution → test-report-{module}.md + screenshots
```

---

### `test-generation` — Test Case Generator

> **Model:** Sonnet · **Skill:** `test-generation:process`

Reads a spec file (never `vars.md`) and produces two artifacts:

- `test-cases.md` — complete, data-agnostic test cases using `${field-name}` placeholders for values and `<<view-id>>` / `{{BASE_URL}}` for navigation — the domain is never resolved here, so the same file runs unmodified against any environment
- `test-data.md` — fillable template with empty slots organized by scenario

**Coverage types:** Happy Path · Smoke · Functional · Edge Cases · Exploratory · Design Comparison (when design reference is provided)

Every test case also gets a **Severity** — Critical, Mid, or Low — judged by business impact rather than derived mechanically from Type (Design Comparison is always Critical). This is what lets `test-execution` later scope a run to only the highest-severity tests. The completion signal includes a `SEVERITY_BREAKDOWN` (Critical/Mid/Low counts) alongside the existing per-type breakdown.

---

### `test-execution` — Browser Test Executor

> **Model:** Sonnet · **Skill:** `test-execution:process` · **MCP:** `playwright_headed`, `figma`, `pencil`

Reads `test-cases.md`, `test-data.md`, and `vars.md`, hydrates `${field-name}` placeholders with concrete values, and resolves every `<<view-id>>` / `{{BASE_URL}}` token into a real URL using `vars.md` — this is the only step in the whole pipeline where `BASE_URL` becomes a concrete domain. Before running anything, filters test cases by `EXECUTION_LEVEL` against their `Severity` (see **Execution Roughness Gate** above) — excluded cases are marked `⏭ SKIPPED` and never executed. Executes every remaining test sequentially via Playwright MCP and captures a timestamped screenshot for every test case regardless of outcome (✅ PASS or ❌ FAIL). Since the agent has no `Bash`/`date` access, every timestamp — report header, Executive Summary, screenshot filenames — is obtained by calling `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate` to read the clock inside the browser page. For Design Comparison test cases, retrieves the original design from Figma MCP or Pencil MCP and compares it against the live implementation, documenting all visual and structural discrepancies. For account-creation test cases, resolves a persistent `AUTH_EMAIL`/`AUTH_PASSWORD` test identity (generating and persisting one to `vars.md` on first use, see **Configuration** below) and verifies any OTP or confirmation email via a second tab on Yopmail — the same shared procedure (`${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md`) that `spec-wizard-generate` uses when a spec's target page itself requires creating an account first (`AUTH_MODE=new`).

| Input | Required | Description |
|---|---|---|
| `EXECUTION_LEVEL` | No | `1` = Critical only, `2` = Critical + Mid, `3` = All. Defaults to `3` if absent (e.g. when invoked directly, bypassing qa-coordinator's roughness gate). |

| Status | Condition |
|---|---|
| ✅ PASS | All steps completed and expected result matched |
| ❌ FAIL | One or more steps did not match the expected result |
| ⚠️ BLOCKED | Test could not run due to environment or data limitations |
| ⏭ SKIPPED | Excluded by the configured `EXECUTION_LEVEL` — never executed |

---

### `spec-wizard` — Legacy Entry Point

> **Model:** Opus · Delegates to `spec-wizard-generate`

Kept for backward compatibility. When invoked, behaves as `spec-wizard-generate`. Prefer using the specific agents directly.

---

## Skills

Each agent loads its skill file at the start of every session. Skills contain step-by-step execution instructions that agents follow exactly.

| Skill | Purpose |
|---|---|
| `spec-wizard:auto-generate` | Navigate → analyze DOM → generate spec in memory → enrich with requirements → save |
| `spec-wizard:improve` | 9-section interactive wizard for refining an existing spec |
| `spec-wizard:pipeline-offer` | Summarize spec → offer QA pipeline dispatch |
| `test-generation:process` | Read spec → determine coverage → write test-cases.md + test-data.md |
| `test-execution:process` | Hydrate → execute via Playwright MCP → classify results → write report |
| `shared:account-identity` | Shared procedure — generate/detect a Yopmail test identity, create/confirm the account, persist to `vars.md`. Followed by both `spec-wizard:auto-generate` and `test-execution:process`, never duplicated. |

---

## Pipeline State Machine

The system uses shell hooks and a `.pipeline-state` file to track progress through the automation pipeline. State transitions happen automatically based on file writes and user responses.

```
[spec-wizard-generate auto-generates spec + optional requirements enrichment]
                                    ↓
                            spec written to disk
                                    ↓
SPEC_AUTO_GENERATED → user says yes → WIZARD_REQUESTED → wizard saves → WIZARD_COMPLETE
                    → user says no  → PIPELINE_OFFER_REQUESTED
                                                         ↓
                                              qa-coordinator dispatched
                                                         ↓
                                              GENERATION_COMPLETE
                                                         ↓
                                              user says "done" / "ready"
                                                         ↓
                                              TEST_DATA_READY
                                                         ↓
                                              test-execution dispatch attempted
                                                         ↓
                              ┌──── auto mode, or EXECUTION_LEVEL already known ────┐
                              ↓                                                     │
                    test-execution dispatched                                       │
                              │                                                     │
                              ↓                                            not auto mode,
                     EXECUTION_COMPLETE                                    no level yet
                                                                                     │
                                                                                     ↓
                                                                     AWAITING_EXECUTION_LEVEL
                                                                                     ↓
                                                                     user answers 1 / 2 / 3
                                                                                     ↓
                                                                          TEST_DATA_READY
                                                                        (retry dispatch, above)
```

> The requirements enrichment step happens **before** the spec is written to disk, so it does not introduce new pipeline states. The `SPEC_AUTO_GENERATED` state is set only after the enriched spec is saved. `AWAITING_EXECUTION_LEVEL` is a detour off `TEST_DATA_READY`, not a new terminal stage — it always resolves back into the same dispatch step, now carrying `EXECUTION_LEVEL`.

**Hooks:**

| Hook | Trigger | Purpose |
|---|---|---|
| `pipeline-on-user-prompt.sh` | Every user message | Routes "yes/no/done" responses to next stage; resolves 1/2/3 execution-level replies |
| `pipeline-on-spec-created.sh` | After Write tool | Detects spec file creation in `Platform/` |
| `pipeline-on-tests-generated.sh` | After Write tool | Detects `test-cases.md` creation |
| `pipeline-on-report-written.sh` | After Write tool | Detects `test-report-*.md` creation |
| `pipeline-on-execution-dispatch.sh` | Before the Agent tool dispatches test-execution | Checks `permission_mode`; blocks the dispatch if not auto mode and no `EXECUTION_LEVEL` is set yet |

---

## Configuration

### `vars.md` — Project configuration

```
BASE_URL = https://your-app.example.com
AUTH_EMAIL = admin@your-app.example.com
AUTH_PASSWORD = your-password
```

Generated test cases never contain a resolved `BASE_URL` — they reference views symbolically (`<<view-id>>` / `{{BASE_URL}}`) and only the test-execution agent reads `vars.md` to resolve `BASE_URL` into a real URL, at run time. This means switching environments (dev/staging/prod) is just a matter of editing `BASE_URL` in `vars.md` — no test case ever needs to be regenerated. Authentication credentials are stored here as named variables — agents reference them by variable name (e.g. `email: AUTH_EMAIL, password: AUTH_PASSWORD`) and read the actual values at runtime. This keeps credentials out of prompts and chat history.

**Persistent test identity.** While `AUTH_EMAIL` / `AUTH_PASSWORD` hold their placeholder values, both `test-execution` and `spec-wizard-generate` (when invoked with `AUTH_MODE=new`) treat them as unset. The first time either flow needs to create an account — `test-execution` running a signup/account-creation test case, or `spec-wizard-generate` analyzing a page that requires a new account first — it generates a `qa-{random}@yopmail.com` identity, verifies it via a second-tab Yopmail check (see below), and overwrites these two lines with the real values — so every subsequent run of either flow, and every other test case requiring a logged-in state, reuses that same account instead of creating a new one. Restore the placeholders to force a fresh account on the next run. This procedure is defined once, in `${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md`, and followed identically by both agents.

You can define custom variable names for different environments or roles:

```
BASE_URL = https://staging.myapp.com
ADMIN_EMAIL = admin@myapp.com
ADMIN_PASSWORD = admin-secret
USER_EMAIL = user@myapp.com
USER_PASSWORD = user-secret
```

### `.mcp.json` — MCP server configuration

Two MCP servers are configured:

- **`playwright_headed`** — All agents use `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__` prefixed tool calls for browser automation. No programmatic Playwright code is ever written or executed.
- **`figma`** — Used by `test-execution` for Design Comparison test cases when a Figma frame URL is provided. Requires a `FIGMA_ACCESS_TOKEN` environment variable.

Set the Figma token once in your shell profile:

```bash
export FIGMA_ACCESS_TOKEN=fig_xxxxxxxxxxxxx   # add to ~/.zshrc or ~/.bashrc
```

If `FIGMA_ACCESS_TOKEN` is missing, the Figma MCP server won't start — Playwright still works normally. Pencil MCP requires no additional configuration.

---

## Spec Format — `TEMPLATE.md`

Every UI screen is described in a single `{module}-description.md` file following the conventions in `TEMPLATE.md`.

### ID conventions

| Entity | Format | Example |
|---|---|---|
| View | `<<readable-name-uuid>>` | `<<login-page-eea0589e>>` |
| Component | `<<readable-name-uuid>>` | `<<login-form-ca815574>>` |
| Business Rule | `<<rule-name-uuid>>` | `<<auth-rule-f3a9c1b2>>` |
| Interactive element | `${field-name}` | `${login-email}`, `${submit-button}` |
| `vars.md` variable | `{{VARIABLE_NAME}}` | `{{BASE_URL}}` |

> **Never hardcode `BASE_URL`.** Navigation to a spec'd view is always written as `<<view-id>>`; an ad-hoc path not backed by a view is written as `{{BASE_URL}}` + path (e.g. `{{BASE_URL}}/reset-password?token=${token}`). Both stay literal in `test-cases.md` and `test-data.md` — only `test-execution` resolves them, at run time, from `vars.md`.

### Spec sections

| Section | Description |
|---|---|
| Screen Identification | View ID, Name, Version, Route, Design Reference (Pencil/Figma) |
| Origin Context | Previous view and start flow |
| Components | Named UI sections with fields, validations, and component-level rules |
| View-Level Fields | Interactive elements not belonging to any component |
| Screen States | Named states and transitions (loading, error, success, empty) |
| Related Views | Spec-file dependencies and external services for cross-view testing |
| Business Rules | Domain rules beyond individual field validations |
| Actions and Transitions | Every user-triggered action and its expected reaction |
| Detailed Flow Description | Step-by-step narrative using `<<view-ids>>` and `${field-names}` |

---

## Workflow Examples

### Create a spec from a live page (auto-generate + requirements enrichment + improve)

```
Invoke: spec-wizard-generate
"Create a spec for /vacantes, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD, destination /vacantes"
→ auto-generates spec in memory from live DOM analysis
→ asks: "Requirements enrichment?" → provide /path/to/requirements.md (or "docs" / "skip")
→ extracts relevant requirements → refines spec in memory
→ saves enriched Platform/Vacantes/vacantes-description.md
→ asks: "Run the improvement wizard?" → yes
→ spec-wizard-improve walks through 9 sections
→ spec-wizard-pipeline shows summary and offers QA pipeline → yes
→ qa-coordinator generates tests, pauses for test-data.md
→ you fill test-data.md → confirm
→ test-execution runs and delivers the report
```

### Create a spec with design comparison

```
Invoke: spec-wizard-generate
"Create a spec for /dashboard, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD,
design reference: https://www.figma.com/design/abc123/MyProject?node-id=1234-5678"
→ auto-generates spec with Figma frame URL in Screen Identification
→ test generation includes a TC-DC-01 Design Comparison test case
→ test execution retrieves the Figma design and compares against the live page
→ report includes a DESIGN COMPARISON section with discrepancy details
```

### Create a spec for a page that requires a brand-new account

```
Invoke: spec-wizard-generate
"Create a spec for /account/settings, new account at /signup with email: AUTH_EMAIL,
password: AUTH_PASSWORD, destination /account/settings"
→ AUTH_EMAIL / AUTH_PASSWORD in vars.md are still placeholders
→ generates qa-{random}@yopmail.com + a matching password
→ submits the signup form at /signup with the generated identity
→ if the app sends a confirmation email or OTP, opens a second tab on yopmail.com,
  retrieves it, and continues the flow — no user input needed
→ once account creation succeeds, persists the real values into vars.md
→ navigates to /account/settings and generates the spec from the live DOM
```

### Run the pipeline on an existing spec

```
Invoke: qa-coordinator
"Run the full QA pipeline for Platform/Login/login-description.md"
→ dispatches test-generation → test-cases.md + test-data.md
→ pauses: "Fill test-data.md and confirm when ready"
→ you fill test-data.md → confirm
→ dispatches test-execution → test-report-login.md generated
```

### Run the pipeline with the execution roughness gate (not in auto mode)

```
Invoke: qa-coordinator
"Run the full QA pipeline for Platform/Login/login-description.md"
→ test-generation reports SEVERITY_BREAKDOWN: 6 Critical / 9 Mid / 3 Low
→ you fill test-data.md → confirm
→ dispatch attempt is blocked (not auto mode, no level specified)
→ qa-coordinator asks: "1 — Critical only (6) · 2 — Critical + Mid (15) · 3 — All (18)"
→ you reply "2"
→ dispatch retries with EXECUTION_LEVEL: 2
→ test-execution runs 15 tests, marks the 3 Low-severity ones ⏭ SKIPPED
→ test-report-login.md generated with the skip breakdown
```

Skip the question entirely by stating the level upfront — this works the same whether or not auto mode is on:

```
Invoke: qa-coordinator
"Run the full QA pipeline for Platform/Login/login-description.md, just the critical tests"
→ qa-coordinator parses "just the critical tests" as EXECUTION_LEVEL 1
→ dispatch goes straight through, no question asked
```

---

## Traceability

Every artifact is linked:

```
{module}-description.md
    └── test-cases.md          references <<view-id>> and ${field-names} from spec
    └── test-data.md           provides concrete values per scenario
    └── test-report-{module}.md  records PASS/FAIL/BLOCKED/SKIPPED per TC ID + execution level + execution window
    └── TC-*.png               timestamped screenshot evidence linked to TC IDs in the report
```

Test IDs follow the format `TC-{TYPE}-{NN}` (e.g. `TC-SMK-01`, `TC-HP-01`). Screenshots follow `{TC-ID}-{short-description}-{filename-timestamp}.png` (e.g. `TC-SMK-01-page-loaded-20260703-143205.png`) — evidence is captured for every ✅ PASS and ❌ FAIL case; ⚠️ BLOCKED cases never execute, so there's nothing to capture.

---

## Contributing and Forking

### Understanding the file layout

Every modifiable part of the system lives in one of these four directories at the repo root:

| Directory | What it contains | How to modify |
|---|---|---|
| `agents/` | Agent definitions (frontmatter + system prompt) | Edit the `.md` file for the agent you want to change |
| `skills/` | Step-by-step execution instructions | Edit the `SKILL.md` inside the relevant subdirectory |
| `hooks/` | Pipeline state machine (bash scripts) | Edit the `.sh` scripts; all use relative path resolution |
| Root files | `TEMPLATE.md`, `vars.md`, `settings.json`, `.mcp.json` | Edit directly |

See [personal-explanation.md](personal-explanation.md) for a deep-dive into how agents, skills, and hooks work together — including the exact data flow, state machine logic, and examples from this project.

### Forking for a new use case

```bash
git clone https://github.com/Strako/AI-Driven-UI-Specification-QA-Automation-Suite.git my-custom-plugin
cd my-custom-plugin

# Modify what you need
# agents/ → change agent behavior or add new agents
# skills/ → change execution procedures
# hooks/ → change pipeline state transitions
# TEMPLATE.md → change the spec format

# Test locally by launching Claude Code with your plugin dir
claude --plugin-dir ./my-custom-plugin
```

### Adding a new agent

1. Create `agents/my-agent.md` with the required frontmatter:

```markdown
---
name: my-agent
description: What this agent does and when to invoke it.
model: claude-sonnet-4-6
color: "#16A34A"
tools: Read, Write, Glob
---

Your agent's system prompt here.
```

2. If the agent needs a skill, create `skills/my-agent:process/SKILL.md` and point to it from the agent's system prompt.

3. Update `package.json` version and push.

### Updating the plugin after changes

```bash
git add .
git commit -m "feat: describe your change"
git push

# Users update with:
claude plugin update AI-Driven-UI-Specification
```
