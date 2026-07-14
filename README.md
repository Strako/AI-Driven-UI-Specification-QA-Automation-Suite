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
#    Place .md or .csv requirement files here — the spec generator scans this
#    folder automatically before every first-time spec save, no prompt needed
#    (.xlsx files are skipped as unreadable — re-export as .md or .csv)
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
│  qa-coordinator  ◄── always the entry point for a spec-creation request   │
│       │              (a PreToolUse hook redirects any direct dispatch     │
│       │               of spec-wizard-generate back here)                  │
│       ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  SPEC CREATION — Stage 0, dispatched by qa-coordinator              │   │
│  │                                                                     │   │
│  │  spec-wizard-generate                                               │   │
│  │       │                                                             │   │
│  │       ├── 1. Playwright analysis (DOM + screenshots)                │   │
│  │       ├── 2. Auto-generate spec in memory                           │   │
│  │       ├── 3. Automatic docs/ folder enrichment (silent, no          │   │
│  │       │        question asked — applied only if docs/ exists)       │   │
│  │       └── 4. Save {module}-description.md, report back to          │   │
│  │              qa-coordinator (never dispatches another agent)        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                       │
│                    qa-coordinator attempts Stage 1 immediately             │
│                    (gated once: "run the improvement wizard first?")       │
│                              yes ──► spec-wizard-improve ──► reports       │
│                              │        back to qa-coordinator directly      │
│                              no ──────────────────────────┐                │
│                                    │◄───────────────────────┘             │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  QA PIPELINE (qa-coordinator + 2 agents) — always runs through,     │   │
│  │  no "run the pipeline?" question anywhere in this default flow      │   │
│  │                                                                     │   │
│  │  qa-coordinator                                                     │   │
│  │       │                                                             │   │
│  │       ├── test-generation ──► test-cases.md + test-data.md          │   │
│  │       │        (auto-filled from vars.md + inference only if        │   │
│  │       │         requested upfront — otherwise left blank)           │   │
│  │       │                                                             │   │
│  │       │   [PAUSE — user fills test-data.md, ALWAYS, regardless      │   │
│  │       │    of auto mode, unless auto-fill was requested upfront]    │   │
│  │       │                                                             │   │
│  │       └── test-execution ──► test-report-{module}.md + screenshots  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

> A **separate standalone path** — explicitly invoking `spec-wizard-improve` or `spec-wizard-pipeline` by name on an existing spec, not through `qa-coordinator` — keeps a real "run the pipeline? yes/no" question via `spec-wizard-pipeline`. That path is for deliberate individual-agent use; it never applies to the default entry point above. See **Pipeline State Machine** below for the full gated flow.

> This pause is enforced by the `pipeline-on-execution-dispatch.sh` `PreToolUse` hook — not just an instruction the coordinator agent might skip. Unlike every other pause in this pipeline, it is **not** skipped by Claude Code's **auto** permission mode — the only way to skip it is to explicitly ask for automatic test data generation in your initial request. Otherwise the pipeline always blocks until you confirm `test-data.md` is filled in, even in auto mode. See **Stage Gate — Test Data Confirmation** below.

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
│   ├── pipeline-on-spec-write-gate.sh  Gates first-time spec saves: automatic docs/ enrichment check (no prompt, no permission-mode dependency)
│   ├── pipeline-on-spec-dispatch.sh    Redirects direct spec-wizard-generate dispatches to qa-coordinator; gates the wizard-offer (qa-coordinator's own Stage 1 dispatch) and the standalone pipeline-offer hand-off
│   ├── pipeline-on-tests-generated.sh  Creates evidences/ on test-cases.md write; sets GENERATION_COMPLETE on the later test-data.md write
│   ├── pipeline-on-test-data-edit-gate.sh  Gates every Write/Edit of test-data.md while state is GENERATION_COMPLETE for that module (blocks regardless of permission_mode — closes the gap where an assistant could fill/overwrite it directly instead of dispatching test-execution)
│   ├── pipeline-on-report-written.sh   Detects report writes → marks complete
│   ├── pipeline-on-execution-dispatch.sh  Gates test-execution dispatch: test-data confirmation (skipped ONLY by an explicit auto-fill request, never by auto mode alone), then execution roughness (skipped in auto mode)
│   ├── pipeline-verify-report.sh       Enforces that test-report-{module}.md really exists on disk (SubagentStop/Stop) → recovers/synthesizes it if not
│   └── verify_execution_report.py      Parsing/validation/recovery logic for pipeline-verify-report.sh
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
│       └── evidences/               created automatically when test-cases.md is generated
│           └── TC-*.png             timestamped screenshot evidence per test
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

Navigates to a live page with Playwright MCP, analyzes the full DOM (including scrolling, tabs, and expandable sections), and produces a complete `{module}-description.md` spec file in one pass — no interactive interview required. This agent is always dispatched by **`qa-coordinator`**'s Stage 0 bootstrap — it is not a top-level entry point for a human's "create a spec" request; a `PreToolUse` hook (`pipeline-on-spec-dispatch.sh`) blocks and redirects any direct dispatch that doesn't carry qa-coordinator's `CALLER` marker.

Before writing the spec to disk, automatically enriches it with project requirements — silently, with no question ever asked:

- **`docs/` folder** → if a `docs/` folder exists at the project root (derived by locating `vars.md` via Glob) with at least one readable `.md`/`.csv` file, a `PreToolUse` hook (`pipeline-on-spec-write-gate.sh`) blocks the very first save of the spec exactly once so the agent scans those files, extracts requirements relevant to this view, and refines the spec in memory before retrying. If `docs/` doesn't exist or has nothing readable, the write proceeds immediately — no prompt, no delay, in every mode.
- **`REQUIREMENTS_NOTE`** → when dispatched by `qa-coordinator`'s Stage 0 with inline business rules extracted from the original request (e.g. multi-role credential pairs), those are applied in addition to, not instead of, the `docs/` check above.

After saving, always emits `---SPEC-GENERATED---` and stops — it never dispatches another agent itself. Control returns to `qa-coordinator`, which owns the decision of whether to offer the improvement wizard next (see `qa-coordinator`'s Stage 0.5 below).

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

After saving: if `CALLER` is present (dispatched by `qa-coordinator`'s Stage 0.5), reports back directly and stops — `qa-coordinator` continues the full pipeline on its own, no further question. If `CALLER` is absent (invoked standalone by a human on an existing spec), automatically invokes `spec-wizard-pipeline` instead, which asks a real "run the pipeline?" question.

| Input | Required | Description |
|---|---|---|
| `SPEC_FILE` | Yes | Path to the existing spec `.md` file |
| `PROJECT_ROOT` | No | Project root path (auto-detected if omitted) |
| `CALLER` | No | Name of the orchestrating agent (`qa-coordinator`) when dispatched non-standalone — changes completion behavior above |

**Sections reviewed (in order):** Screen Identification · Origin Context · Components (one at a time) · View-Level Fields · Screen States · Related Views · Business Rules · Actions and Transitions · Detailed Flow Description

---

### `spec-wizard-pipeline` — Pipeline Offer

> **Model:** Opus · **Skill:** `spec-wizard:pipeline-offer`

Reads a completed spec file, shows a structured summary (components, fields, states, rules, actions), and offers to launch the full QA pipeline via `qa-coordinator`. **This is a standalone tool, not part of qa-coordinator's default flow** — it's only reached by explicitly invoking `spec-wizard-improve` or `spec-wizard-pipeline` by name on an existing spec. In that context, the "run the pipeline? yes/no" question it asks is a real, deliberate choice — unlike `qa-coordinator`'s own default flow, which has no such question and always runs the pipeline through to a report once reached.

| Input | Required | Description |
|---|---|---|
| `SPEC_FILE` | Yes | Path to the completed spec file |
| `PROJECT_ROOT` | No | Project root path (auto-detected if omitted) |

---

### `qa-coordinator` — Pipeline Orchestrator

> **Model:** Opus · **Dispatches:** `spec-wizard-generate`, `spec-wizard-improve`, `test-generation`, `test-execution`

Collects a spec file path, then runs the full pipeline or individual stages. Always uses headed browser mode. Optionally pauses once, right after a fresh spec bootstrap, to offer the improvement wizard (**Stage 0.5**, gated by a `PreToolUse` hook — not a real "run the pipeline?" fork, just whether to review the spec first; see below). Also pauses between generation and execution for the user to fill `test-data.md` — enforced by a `PreToolUse` hook, not just an instruction. Unlike every other pause in this pipeline, this one is **not** affected by Claude Code's **auto** permission mode; it only skips when the initial request explicitly asked for automatic test data generation (see **Stage Gate — Test Data Confirmation** below). After execution, the final summary includes the results breakdown plus an **execution window** (`{STARTED} – {COMPLETED}`) taken from the test-execution report timestamps.

This is the entry point for **any** spec-creation or "spec + test this page/module" request — even a bare "create a spec for X" with no mention of tests, even without an explicit `@qa-coordinator` mention or a full URL. A `PreToolUse` hook (`pipeline-on-spec-dispatch.sh`) enforces this deterministically: any direct dispatch of `spec-wizard-generate` (or its legacy alias `spec-wizard`) that doesn't carry qa-coordinator's own `CALLER` marker is blocked and redirected here instead. It always reads `vars.md` first (for `BASE_URL` and existing credentials) before asking the user anything. If no matching spec file exists yet, it doesn't stop and ask for a URL — it runs **Stage 0 — Spec Bootstrap**: derives `PAGE_URL`/`MODULE_NAME`/`AUTH_REQUIRED` and any role-based credential variables (e.g. `CLIENT_EMAIL`/`CLIENT_PASSWORD`, `PROVIDER_EMAIL`/`PROVIDER_PASSWORD`) from the request and `vars.md`, then dispatches `spec-wizard-generate` non-interactively (`CALLER: qa-coordinator`) to create it before continuing into Stage 1.

| Mode | Trigger |
|---|---|
| **Full Pipeline** (default) | No specific stage mentioned |
| **Generate Only** | "generate", "test cases only", "create tests" |
| **Execute Only** | "execute", "run tests", "only execute" |

Every attempt to dispatch `test-execution` passes through the same `pipeline-on-execution-dispatch.sh` `PreToolUse` hook, which runs two ordered gates with **different** relationships to Claude Code's **auto** permission mode — see each gate below.

**Test Data Confirmation Gate** — checked first, and **not** affected by auto mode. If the pipeline state shows test cases were just generated and no confirmation reply has been seen yet for this module, the hook blocks the dispatch and `qa-coordinator` asks you to fill in `test-data.md` and reply when ready (e.g. "done") — this happens **even in auto mode**. The `UserPromptSubmit` hook recognizes the reply and retries the dispatch, which then moves on to the roughness gate below. The only way to skip this gate is to explicitly ask for automatic test data generation in your initial request (see `test-generation`'s `AUTO_FILL_TEST_DATA` below) — `qa-coordinator` then includes `AUTO_TEST_DATA: true` on the dispatch and the hook lets it through unconditionally.

**Execution Roughness Gate** — checked once test data is confirmed (or auto-generation was requested upfront). This one **is** affected by auto mode:

- If the initiating message already states a level explicitly (e.g. "just run the critical tests"), that always wins — no question is asked, in either mode.
- Otherwise, in **auto** mode, execution defaults to running **all** test cases (level 3).
- Otherwise (not auto mode, no explicit level), the hook blocks the dispatch and `qa-coordinator` asks the user directly:

  > **1** — Critical only · **2** — Critical + Mid · **3** — All

  using the Critical/Mid/Low counts from test-generation's `SEVERITY_BREAKDOWN`. Once answered, the dispatch retries with `EXECUTION_LEVEL` set.

**Pipeline flow:**

```
spec file → test-generation → test-cases.md + test-data.md
                                    │
        [GATE — test-data confirmation; skipped ONLY if auto-fill was requested upfront]
                                    │
                    [GATE — execution roughness level; skipped in auto mode or if pre-stated]
                                    │
                              test-execution → test-report-{module}.md + screenshots
```

---

### `test-generation` — Test Case Generator

> **Model:** Sonnet · **Skill:** `test-generation:process`

Reads a spec file and produces two artifacts:

- `test-cases.md` — complete, data-agnostic test cases using `${field-name}` placeholders for values and `<<view-id>>` / `{{BASE_URL}}` for navigation — the domain is never resolved here, so the same file runs unmodified against any environment. `vars.md` is never read for this artifact.
- `test-data.md` — organized by scenario. Empty fill-in slots by default; if `AUTO_FILL_TEST_DATA: true` is set (only when `qa-coordinator` parsed an explicit "generate test data automatically" request at Startup), every field is instead filled with a concrete value — a real credential read from `vars.md` for fields tied to a named variable, or a plausible inferred value otherwise. Signup/registration credential fields are always left blank regardless, since `test-execution` generates and confirms those itself via Yopmail.

**Coverage types:** Happy Path · Smoke · Functional · Edge Cases · Exploratory · Design Comparison (when design reference is provided)

Every test case also gets a **Severity** — Critical, Mid, or Low — judged by business impact rather than derived mechanically from Type (Design Comparison is always Critical). This is what lets `test-execution` later scope a run to only the highest-severity tests. The completion signal includes a `SEVERITY_BREAKDOWN` (Critical/Mid/Low counts) alongside the existing per-type breakdown and a `TEST_DATA_AUTO_FILLED` flag.

---

### `test-execution` — Browser Test Executor

> **Model:** Sonnet · **Skill:** `test-execution:process` · **MCP:** `playwright_headed`, `figma`, `pencil`

Reads `test-cases.md`, `test-data.md`, and `vars.md`, hydrates `${field-name}` placeholders with concrete values, and resolves every `<<view-id>>` / `{{BASE_URL}}` token into a real URL using `vars.md` — this is the only step in the whole pipeline where `BASE_URL` becomes a concrete domain. Before running anything, filters test cases by `EXECUTION_LEVEL` against their `Severity` (see **Execution Roughness Gate** above) — excluded cases are marked `⏭ SKIPPED` and never executed. Executes every remaining test sequentially via Playwright MCP and captures a timestamped screenshot for every test case regardless of outcome (✅ PASS or ❌ FAIL). Since the agent has no `Bash`/`date` access, every timestamp — report header, Executive Summary, per-test-case timestamps, screenshot filenames — is obtained by calling `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate` to read the clock inside the browser page. Every executed test case's own timestamp and evidence file path are written directly into its row in the report's section tables, not just cross-referenced separately in the Captured Screenshots table. For Design Comparison test cases, retrieves the original design from Figma MCP or Pencil MCP and compares it against the live implementation, documenting all visual and structural discrepancies. For account-creation test cases, resolves a persistent `AUTH_EMAIL`/`AUTH_PASSWORD` test identity (generating and persisting one to `vars.md` on first use, see **Configuration** below) and verifies any OTP or confirmation email via a second tab on Yopmail — the same shared procedure (`${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md`) that `spec-wizard-generate` uses when a spec's target page itself requires creating an account first (`AUTH_MODE=new`).

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

Kept for backward compatibility. When invoked, behaves as `spec-wizard-generate`. Prefer using the specific agents directly. Subject to the same entry-point redirect as `spec-wizard-generate` — `pipeline-on-spec-dispatch.sh` blocks any direct dispatch of this agent too and redirects to `qa-coordinator`.

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
[human, or top-level Claude, attempts to dispatch spec-wizard-generate directly]
                                    ↓
                    Agent-tool dispatch attempted (subagent_type = spec-wizard-generate)
                                    ↓
                    ┌────── carries CALLER: qa-coordinator? ──────┐
                   yes                                            no
                    ↓                                              ↓
        (bootstrap dispatch — let through,          BLOCKED — redirect to qa-coordinator
         record SPEC_BOOTSTRAP marker)                            ↓
                    ↓                                qa-coordinator dispatched instead,
                    │                                 which runs its own Stage 0 bootstrap
                    │                                 (dispatches spec-wizard-generate itself,
                    │                                  now WITH the CALLER marker) ──────┐
                    ↓                                                                    │
[spec-wizard-generate analyzes the page, builds the spec draft in memory] ◄──────────────┘
                                    ↓
                    Write attempted (spec file, first save for this module)
                                    ↓
        ┌── bootstrap marker present, OR docs/ has nothing readable ──┐
        ↓                                                             │
  Write succeeds                                                      │
        ↓                                                    docs/ has readable .md/.csv files
  SPEC_AUTO_GENERATED                                                 │
        │                                          DOCS_ENRICHMENT marker touched,
        │                                          Write blocked once (no human involved)
        │                                                             ↓
        │                                        agent scans docs/, applies relevant
        │                                        requirements to in-memory draft,
        │                                        retries Write → succeeds
        │                                                             ↓
        └─────────────────────────────────────────────→ SPEC_AUTO_GENERATED
                                    ↓
        qa-coordinator (Stage 1) attempts to dispatch test-generation
        immediately — includes PIPELINE_STAGE: test-generation
                                    ↓
        ┌── spec NOT bootstrapped this run, OR wizard already resolved ──┐
        ↓                                                                │
  (gate is a no-op — this only ever fires right after a fresh            │
   bootstrap in the SAME run; a pipeline run against a spec the          │
   user pointed to directly skips straight past it)                     │
        │                                              spec WAS just bootstrapped
        │                                              this run, wizard not yet resolved
        │                                                                ↓
        │                                              ┌────── auto mode ──────┐
        │                                              ↓                       │
        │                                    (skip wizard by default)   not auto mode
        │                                              │                       ↓
        │                                              │         WIZARD_OFFER_PENDING (blocked)
        │                                              │                       ↓
        │                                              │        ┌── yes ───────┴────── no ──┐
        │                                              │        ↓                           ↓
        │                                              │  qa-coordinator dispatches   WIZARD_OFFER_ANSWERED
        │                                              │  spec-wizard-improve                ↓
        │                                              │  (CALLER: qa-coordinator)    (retry dispatch)
        │                                              │        ↓                           │
        │                                              │  wizard saves → WIZARD_COMPLETE     │
        │                                              │  → reports back to qa-coordinator   │
        │                                              │  (does NOT dispatch                 │
        │                                              │   spec-wizard-pipeline — CALLER      │
        │                                              │   present skips that entirely)      │
        │                                              │        ↓                           │
        │                                              └──── retry Stage 1 dispatch ─────────┘
        └─────────────────────────────────────────────────────────┬──────────────────────────┘
                                                                     ↓
                                                          test-generation dispatched
                                                                     ↓
                                              GENERATION_COMPLETE
                                        (test-generation auto-filled test-data.md IF
                                         REQUESTED_AUTO_TEST_DATA was set at Startup)
                                                         ↓
                    test-execution dispatch attempted (immediately, includes
                        AUTO_TEST_DATA: true ONLY if auto-fill was requested)
                                                         ↓
                            ┌────────── AUTO_TEST_DATA: true present? ──────────┐
                           yes                                                  no
                            ↓                                                    ↓
                (test-data gate bypassed —                     test data confirmed for this module?
                 NOT affected by auto mode                                       │
                 at all; only this explicit                    ┌────── no ──────┴────── yes ──┐
                 upfront request skips it)                      ↓                              ↓
                            │                        (blocked; state stays        EXECUTION_LEVEL known?
                            │                         GENERATION_COMPLETE —                    │
                            │                         even in auto mode)          ┌── no ───────┴──── yes ──┐
                            │                                   ↓                  ↓                        ↓
                            │                     user says "done" / "ready"  AWAITING_       test-execution
                            │                                   ↓             EXECUTION_LEVEL  dispatched
                            │                            TEST_DATA_READY            ↓                ↓
                            │                                   │           user answers 1/2/3  EXECUTION_
                            │                                   └─── retry ──────────┘           COMPLETE
                            └───────────────────────────────────────────────────────┘
                            (once past the test-data gate, still passes through the
                             Execution Roughness Gate, which IS bypassed by auto mode
                             — see the two-gate table under `pipeline-on-execution-dispatch.sh`)
```

> This diagram is qa-coordinator's **default** flow — the only one reachable from a generic "create a spec for X" or "spec + test this page" request. There is no "run the QA pipeline?" fork anywhere in it; reaching qa-coordinator at all already commits to running the full pipeline through to a report. A **separate, standalone path** exists purely for explicit individual-agent use: invoking `spec-wizard-improve` or `spec-wizard-pipeline` **by name** on an existing spec (not through qa-coordinator) keeps the old behavior — the wizard, if used, auto-chains into `spec-wizard-pipeline`, which shows a spec summary and asks a real "run the pipeline? yes/no" (gated by the same `pipeline-on-spec-dispatch.sh`, `QA_PIPELINE_OFFER_PENDING`/`QA_PIPELINE_CONFIRMED` states) before dispatching `qa-coordinator` itself. These two paths never overlap: qa-coordinator's own Stage 0.5 dispatches `spec-wizard-improve` with `CALLER: qa-coordinator`, which skips the `spec-wizard-pipeline` hand-off entirely and reports straight back.
>
> Every hand-off between stages follows the same pattern: the dispatching agent always **attempts** the next step immediately — it never decides on its own to ask a question or wait — and a `PreToolUse` hook is the only place that can see Claude Code's `permission_mode`, so it alone decides whether to let the attempt through silently or block it (`exit 2`) with instructions to ask a human first. Nothing in this pipeline relies on the model correctly inferring "we're in auto mode, skip this" from its own prompt text — that inference is impossible for the model to make reliably since `permission_mode` is never exposed to it directly, only to hooks. Not every gate treats auto mode the same way, though: the **entry-point redirect** and the **docs/ enrichment gate** are unconditional (they never depend on permission_mode at all — the first is a routing rule, the second is a pure filesystem check), the **test-data confirmation gate** deliberately ignores auto mode (it only bypasses on an explicit upfront auto-fill request), while the **wizard-offer** (qa-coordinator's Stage 0.5), the standalone **pipeline-offer**, and the **execution roughness** gates all do bypass in auto mode. `SPEC_BOOTSTRAP` and `DOCS_ENRICHMENT` are per-module marker files (not `.pipeline-state` values) — the first records that qa-coordinator's Stage 0 dispatch is non-interactive by contract, the second records that the docs/ check has already been resolved for this module's first save so a retry doesn't re-block. `AWAITING_EXECUTION_LEVEL` is a detour that only occurs after test data is confirmed — it always resolves back into a dispatch retry, now carrying `EXECUTION_LEVEL`, at which point the test-data gate is already satisfied and only the roughness gate remains.

**Hooks:**

| Hook | Trigger | Purpose |
|---|---|---|
| `pipeline-on-user-prompt.sh` | Every user message | Routes replies (wizard yes-no / pipeline yes-no / "done" / 1-2-3) to the next stage |
| `pipeline-on-spec-created.sh` | After Write tool | Detects spec file creation in `Platform/`, tracks `SPEC_AUTO_GENERATED` / `WIZARD_COMPLETE` |
| `pipeline-on-spec-write-gate.sh` | Before Write tool | Gates the *first* save of a new module's spec file: checks whether the project's `docs/` folder has anything readable and, if so, blocks the write exactly once (no human involved, no dependency on `permission_mode`) so the agent applies it and retries. No-op if `docs/` is empty/absent, or the file already exists (a resave). |
| `pipeline-on-spec-dispatch.sh` | Before the Agent tool dispatches an agent | Three things: (1) **entry-point redirect** — blocks any dispatch of `spec-wizard-generate`/`spec-wizard` lacking qa-coordinator's `CALLER` marker, regardless of `permission_mode`; (2) gates `qa-coordinator → test-generation` (Stage 1), the wizard-offer question, but **only** right after a Stage 0 bootstrap in the same run — a pipeline run against a pre-existing spec skips this gate entirely; (3) gates the **standalone-only** `spec-wizard-pipeline → qa-coordinator` hand-off (run-the-pipeline offer). (2) and (3) use the same auto-mode-bypass pattern as the execution-dispatch gate. Also records the `SPEC_BOOTSTRAP` marker for qa-coordinator's Stage 0 dispatch, and — on every `test-generation` (re)dispatch attempt — clears a stale `GENERATION_COMPLETE` left over for that same module from an earlier, never-confirmed run, so `pipeline-on-test-data-edit-gate.sh` doesn't mistake this fresh run's own `test-data.md` write for an unconfirmed leftover pause |
| `pipeline-on-tests-generated.sh` | After Write tool | Creates the module's `evidences/` subfolder on `test-cases.md` creation, since `test-execution` has no `Bash`/mkdir access. Sets `GENERATION_COMPLETE` on the *later* `test-data.md` write (test-generation writes `test-cases.md` first, `test-data.md` second) — keying the state transition off the second write guarantees test-generation's own write is never blocked by `pipeline-on-test-data-edit-gate.sh` below. |
| `pipeline-on-test-data-edit-gate.sh` | Before Write **and** Edit tool calls | Blocks any direct modification of a module's `test-data.md` while its state is `GENERATION_COMPLETE` (unconfirmed) — regardless of `permission_mode`. Closes the gap where `pipeline-on-execution-dispatch.sh` only gated the *dispatch* of test-execution, not a direct `Read`+`Edit`/`Write` of the file itself by an assistant rationalizing "auto mode is active, I'll fill it in myself." |
| `pipeline-on-report-written.sh` | After Write tool | Detects `test-report-*.md` creation |
| `pipeline-on-execution-dispatch.sh` | Before the Agent tool dispatches test-execution | Two independently-gated checks: test-data confirmation (bypassed **only** by an explicit `AUTO_TEST_DATA: true` marker — never by `permission_mode` alone) and execution roughness (bypassed by auto mode, defaulting to level 3) |
| `pipeline-verify-report.sh` | `SubagentStop` (agent: `test-execution`) and every `Stop` | Reads the agent's own `---EXECUTION-COMPLETE---` signal from the transcript and checks the `REPORT` path it names is really on disk and structurally complete (required sections present, every evidence screenshot linked, timestamps present). If not, recovers the file — from the model's own captured `Write` tool-call content if one exists in the transcript, otherwise a synthesized report built from the signal's counts plus the real files in `evidences/` — then blocks the stop once (exit 2) so the model gets a chance to overwrite it with the authoritative version before finishing. This is what guarantees the report is never just a claim in the chat transcript. |

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

### Create a spec from a live page (auto-generate + docs/ enrichment + improve)

```
Invoke: qa-coordinator          ← always the entry point, even for a spec-only request
"Create a spec for /vacantes, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD, destination /vacantes"
→ Stage 0 bootstrap dispatches spec-wizard-generate non-interactively (CALLER: qa-coordinator)
→ auto-generates spec in memory from live DOM analysis
→ attempts to save Platform/Vacantes/vacantes-description.md
→ docs/ folder exists with requirements.md → write blocked once, no question asked
→ scans docs/, applies relevant requirements to the in-memory draft, retries → saves
→ spec-wizard-generate reports back to qa-coordinator (never dispatches another agent itself)
→ qa-coordinator attempts to dispatch test-generation immediately — this attempt is
  gated once: not in auto mode → blocked, asks "run the improvement wizard first?"
→ you reply "no" → dispatch retries, unblocked → test-generation runs
→ (there is no separate "run the pipeline?" question anywhere in this flow —
   reaching qa-coordinator at all already commits to running it through to a report)
→ qa-coordinator attempts to dispatch test-execution immediately
→ not in auto mode (and no auto-test-data request was made): dispatch is blocked,
  pauses for you to fill test-data.md
→ you fill test-data.md → confirm
→ test-execution runs and delivers the report
```

> A human directly invoking `spec-wizard-generate` (not through qa-coordinator) gets redirected to qa-coordinator automatically by `pipeline-on-spec-dispatch.sh` — there is no way to reach spec-wizard-generate any other way. If you reply "yes" to the improvement-wizard question instead, qa-coordinator dispatches `spec-wizard-improve` (with `CALLER: qa-coordinator`), which reports straight back once you finish the 9-section review — then qa-coordinator continues into test generation exactly as above.

### Create a spec with design comparison

```
Invoke: qa-coordinator
"Create a spec for /dashboard, login at /login with email: AUTH_EMAIL, password: AUTH_PASSWORD,
design reference: https://www.figma.com/design/abc123/MyProject?node-id=1234-5678"
→ Stage 0 bootstrap dispatches spec-wizard-generate, which auto-generates the spec
  with the Figma frame URL in Screen Identification
→ test generation includes a TC-DC-01 Design Comparison test case
→ test execution retrieves the Figma design and compares against the live page
→ report includes a DESIGN COMPARISON section with discrepancy details
```

### Create a spec for a page that requires a brand-new account

```
Invoke: qa-coordinator
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
→ attempts to dispatch test-execution immediately — dispatch is blocked
→ pauses: "Fill test-data.md and confirm when ready"
→ you fill test-data.md → confirm
→ dispatches test-execution → test-report-login.md generated
```

### Run the same pipeline in Claude Code's auto permission mode

```
Invoke: qa-coordinator
"Run the full QA pipeline for Platform/Login/login-description.md"
→ dispatches test-generation → test-cases.md + test-data.md (left blank — no auto-fill requested)
→ attempts to dispatch test-execution immediately
→ auto mode affects ONLY the roughness gate here, not the test-data gate
→ test-data confirmation still blocks — even in auto mode — because auto-fill was not requested
→ pauses: "Fill test-data.md and confirm when ready"
→ you fill test-data.md → confirm
→ dispatch retries: roughness gate is skipped (auto mode), EXECUTION_LEVEL defaults to 3 (All)
→ test-report-login.md generated
```

### Run the pipeline fully unattended, including test data (auto mode + explicit auto-fill request)

```
Invoke: qa-coordinator
"Run the full QA pipeline for Platform/Login/login-description.md, generate the test data automatically"
→ qa-coordinator parses "generate the test data automatically" as REQUESTED_AUTO_TEST_DATA = true
→ dispatches test-generation with AUTO_FILL_TEST_DATA: true
→ test-generation fills every field in test-data.md — real vars.md values for credential
  fields, plausible inferred values everywhere else (signup fields are still left blank)
→ attempts to dispatch test-execution with AUTO_TEST_DATA: true
→ test-data confirmation gate bypasses unconditionally — this is the ONLY thing that skips it,
  auto mode alone would not have been enough
→ roughness gate also bypasses since the session is in auto mode → EXECUTION_LEVEL 3 (All)
→ test-execution runs immediately against the auto-filled data, no pauses at all
→ test-report-login.md generated
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
    └── evidences/TC-*.png     timestamped screenshot evidence linked to TC IDs in the report
```

Test IDs follow the format `TC-{TYPE}-{NN}` (e.g. `TC-SMK-01`, `TC-HP-01`). Screenshots follow `{TC-ID}-{short-description}-{filename-timestamp}.png` (e.g. `TC-SMK-01-page-loaded-20260703-143205.png`) and always live in the module's `evidences/` subfolder, never directly in the module root — created automatically by a hook the moment `test-cases.md` is generated. Evidence is captured for every ✅ PASS and ❌ FAIL case; ⚠️ BLOCKED cases never execute, so there's nothing to capture.

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
