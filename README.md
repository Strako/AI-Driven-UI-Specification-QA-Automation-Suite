# AI-Driven-UI-Specification — QA Automation Suite

A Claude-native agent system for end-to-end UI test automation. From a live page URL to a full test execution report — with automatic spec generation, interactive improvement, and browser-driven test execution.

> **New here?** Read the [User Guide](user-guide.md) for a complete step-by-step walkthrough.

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
│  │  spec-wizard-generate ──► {module}-description.md                   │   │
│  │         │                                                           │   │
│  │         ├── yes ──► spec-wizard-improve (interactive refinement)    │   │
│  │         │                    │                                      │   │
│  │         └── no ────────────-─┼──► spec-wizard-pipeline (summary)    │   │
│  │                              └──► spec-wizard-pipeline (summary)    │   │
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

![Mermaid Diagram](Agentic-flow-diagram/mermaid-diagram.png)

---

## Project Structure

```
.
├── .claude/
│   ├── agents/                          Claude agent definitions
│   │   ├── spec-wizard.md               Legacy entry point (delegates to spec-wizard-generate)
│   │   ├── spec-wizard-generate.md      Auto-generates spec from live page via Playwright
│   │   ├── spec-wizard-improve.md       Interactive section-by-section spec refinement
│   │   ├── spec-wizard-pipeline.md      Shows spec summary and offers QA pipeline
│   │   ├── qa-coordinator.md            Pipeline orchestrator (dispatches gen + exec)
│   │   ├── test-generation.md           Test case generator from spec
│   │   └── test-execution.md            Browser test executor via Playwright MCP
│   │
│   ├── skills/                          Agent skill instructions
│   │   ├── spec-wizard:auto-generate/
│   │   │   └── SKILL.md                 Auto-gen: navigate → analyze → write spec
│   │   ├── spec-wizard:improve/
│   │   │   └── SKILL.md                 9-section interactive improvement wizard
│   │   ├── spec-wizard:pipeline-offer/
│   │   │   └── SKILL.md                 Summarize spec → offer QA pipeline
│   │   ├── spec-wizard:process/
│   │   │   └── SKILL.md                 12-phase full wizard (legacy, used by spec-wizard.md)
│   │   ├── test-generation:process/
│   │   │   └── SKILL.md                 6-step test case generation
│   │   └── test-execution:process/
│   │       └── SKILL.md                 6-step browser test execution
│   │
│   ├── hooks/                           Pipeline state machine hooks
│   │   ├── pipeline-on-user-prompt.sh   Routes user responses to next pipeline stage
│   │   ├── pipeline-on-spec-created.sh  Detects spec file writes → updates state
│   │   ├── pipeline-on-tests-generated.sh  Detects test-cases.md writes → updates state
│   │   └── pipeline-on-report-written.sh   Detects report writes → marks complete
│   │
│   ├── .pipeline-state                  Current pipeline state (auto-managed)
│   └── settings.local.json             Permissions, MCP servers, hook configuration
│
├── Platform/                            Module output directory
│   └── {ModuleName}/                    One folder per UI screen
│       ├── {module}-description.md      UI screen spec (created by spec-wizard)
│       ├── {module}-analysis.png        Screenshot from wizard analysis
│       ├── test-cases.md                Generated test cases (data-agnostic)
│       ├── test-data.md                 Fillable test data template
│       ├── test-report-{module}.md      Execution report with pass/fail/blocked
│       └── TC-*.png                     Screenshot evidence from test execution
│
├── TEMPLATE.md                          Canonical spec format and conventions
├── vars.md                              Project-level configuration (BASE_URL)
├── .mcp.json                            Playwright MCP server configuration
├── README.md                            This file
└── user-guide.md                        Step-by-step usage walkthrough
```

---

## Agents

### `spec-wizard-generate` — Auto Spec Generator

> **Model:** Opus · **Skill:** `spec-wizard:auto-generate` · **MCP:** `playwright_headed`

Navigates to a live page with Playwright MCP, analyzes the full DOM (including scrolling, tabs, and expandable sections), and produces a complete `{module}-description.md` spec file in one pass — no interactive interview required.

After saving, offers two paths:

- **Yes** → launches `spec-wizard-improve` for interactive refinement
- **No** → launches `spec-wizard-pipeline` to offer the QA pipeline

| Input               | Required | Description                                          |
| ------------------- | -------- | ---------------------------------------------------- |
| `PAGE_URL`          | Yes      | Full URL or path to analyze                          |
| `MODULE_NAME`       | No       | Kebab-case name (derived from URL if omitted)        |
| `AUTH_REQUIRED`     | No       | Whether the page needs login first                   |
| `LOGIN_ROUTE`       | If auth  | Route or URL of the login page                       |
| `AUTH_EMAIL`        | If auth  | Login email or username                              |
| `AUTH_PASSWORD`     | If auth  | Login password                                       |
| `DESTINATION_ROUTE` | If auth  | Page to analyze after login                          |
| `OUTPUT_DIR`        | No       | Output directory (default: `Platform/{ModuleName}/`) |

**Output:** `Platform/{ModuleName}/{module}-description.md`

---

### `spec-wizard-improve` — Interactive Spec Refinement

> **Model:** Opus · **Skill:** `spec-wizard:improve`

Takes an existing spec file and walks through all 9 content sections in order. For each section it shows the current content, asks targeted questions, applies changes, and waits for explicit confirmation before advancing.

After saving, automatically invokes `spec-wizard-pipeline`.

| Input          | Required | Description                                  |
| -------------- | -------- | -------------------------------------------- |
| `SPEC_FILE`    | Yes      | Path to the existing spec `.md` file         |
| `PROJECT_ROOT` | No       | Project root path (auto-detected if omitted) |

**Sections reviewed (in order):**

1. Screen Identification
2. Origin Context
3. Components (one at a time, with field-level questions)
4. View-Level Fields
5. Screen States
6. Related Views
7. Business Rules
8. Actions and Transitions
9. Detailed Flow Description

---

### `spec-wizard-pipeline` — Pipeline Offer

> **Model:** Opus · **Skill:** `spec-wizard:pipeline-offer`

Reads a completed spec file, shows a structured summary (components, fields, states, rules, actions), and offers to launch the full QA pipeline via `qa-coordinator`.

| Input          | Required | Description                                  |
| -------------- | -------- | -------------------------------------------- |
| `SPEC_FILE`    | Yes      | Path to the completed spec file              |
| `PROJECT_ROOT` | No       | Project root path (auto-detected if omitted) |

---

### `qa-coordinator` — Pipeline Orchestrator

> **Model:** Opus · **Dispatches:** `test-generation`, `test-execution`

Collects a spec file path, then runs the full pipeline or individual stages. Always uses headed browser mode. Pauses between generation and execution for the user to fill `test-data.md`.

| Mode                        | Trigger                                       |
| --------------------------- | --------------------------------------------- |
| **Full Pipeline** (default) | No specific stage mentioned                   |
| **Generate Only**           | "generate", "test cases only", "create tests" |
| **Execute Only**            | "execute", "run tests", "only execute"        |

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

Reads a spec file and produces two artifacts:

- `test-cases.md` — complete, data-agnostic test cases using `${field-name}` placeholders
- `test-data.md` — fillable template with empty slots organized by scenario

**Coverage types:** Happy Path · Smoke · Functional · Edge Cases · Exploratory

---

### `test-execution` — Browser Test Executor

> **Model:** Sonnet · **Skill:** `test-execution:process` · **MCP:** `playwright_headed`

Reads `test-cases.md` and `test-data.md`, hydrates placeholders with concrete values, executes every test sequentially via Playwright MCP, captures screenshots, and generates a structured report in technical Spanish.

| Status       | Condition                                                 |
| ------------ | --------------------------------------------------------- |
| ✅ PASS      | All steps completed and expected result matched           |
| ❌ FAIL      | One or more steps did not match the expected result       |
| ⚠️ BLOQUEADO | Test could not run due to environment or data limitations |

---

### `spec-wizard` — Legacy Entry Point

> **Model:** Opus · Delegates to `spec-wizard-generate`

Kept for backward compatibility. When invoked, behaves as `spec-wizard-generate`. Prefer using the specific agents directly.

---

## Skills

Each agent loads its skill file at the start of every session. Skills contain step-by-step execution instructions that agents follow exactly.

| Skill                        | Purpose                                                                |
| ---------------------------- | ---------------------------------------------------------------------- |
| `spec-wizard:auto-generate`  | Navigate → analyze DOM → generate complete spec in one pass            |
| `spec-wizard:improve`        | 9-section interactive wizard for refining an existing spec             |
| `spec-wizard:pipeline-offer` | Summarize spec → offer QA pipeline dispatch                            |
| `spec-wizard:process`        | 12-phase full wizard with interview (legacy)                           |
| `test-generation:process`    | Read spec → determine coverage → write test-cases.md + test-data.md    |
| `test-execution:process`     | Hydrate → execute via Playwright MCP → classify results → write report |

---

## Pipeline State Machine

The system uses shell hooks and a `.pipeline-state` file to track progress through the automation pipeline. State transitions happen automatically based on file writes and user responses.

**States:**

```
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
                                              test-execution dispatched
                                                         ↓
                                              EXECUTION_COMPLETE
```

**Hooks:**

| Hook                             | Trigger            | Purpose                                      |
| -------------------------------- | ------------------ | -------------------------------------------- |
| `pipeline-on-user-prompt.sh`     | Every user message | Routes "yes/no/done" responses to next stage |
| `pipeline-on-spec-created.sh`    | After Write tool   | Detects spec file creation in `Platform/`    |
| `pipeline-on-tests-generated.sh` | After Write tool   | Detects `test-cases.md` creation             |
| `pipeline-on-report-written.sh`  | After Write tool   | Detects `test-report-*.md` creation          |

---

## Configuration

### `vars.md` — Project configuration

```
BASE_URL = https://www.google.com
```

All agents read `vars.md` from the project root to resolve `BASE_URL`. This domain is prepended to every route in spec files to form full URLs. Update it when your environment changes.

### `.mcp.json` — Playwright MCP server

```json
{
  "mcpServers": {
    "playwright_headed": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--browser", "chrome"]
    }
  }
}
```

A single headed Playwright MCP server is configured. All agents use `mcp__playwright_headed__` prefixed tool calls for browser automation. No programmatic Playwright code is ever written or executed.

---

## Spec Format — `TEMPLATE.md`

Every UI screen is described in a single `{module}-description.md` file following the conventions in `TEMPLATE.md`. The spec-wizard agents create these files; you can also create or edit them manually.

### ID conventions

| Entity              | Format                   | Example                              |
| ------------------- | ------------------------ | ------------------------------------ |
| View                | `<<readable-name-uuid>>` | `<<login-page-eea0589e-...>>`        |
| Component           | `<<readable-name-uuid>>` | `<<login-form-ca815574-...>>`        |
| Business Rule       | `<<rule-name-uuid>>`     | `<<auth-rule-f3a9c1b2>>`             |
| Interactive element | `${field-name}`          | `${login-email}`, `${submit-button}` |

### Spec sections

| Section                   | Description                                                           |
| ------------------------- | --------------------------------------------------------------------- |
| Screen Identification     | View ID, Name, Version, Route                                         |
| Origin Context            | Previous view and start flow                                          |
| Components                | Named UI sections with fields, validations, and component-level rules |
| View-Level Fields         | Interactive elements not belonging to any component                   |
| Screen States             | Named states and transitions (loading, error, success, empty)         |
| Related Views             | Spec-file dependencies and external services for cross-view testing   |
| Business Rules            | Domain rules beyond individual field validations                      |
| Actions and Transitions   | Every user-triggered action and its expected reaction                 |
| Detailed Flow Description | Step-by-step narrative using `<<view-ids>>` and `${field-names}`      |

---

## Workflow Examples

### Create a spec from a live page (auto-generate + improve)

```
Invoke: spec-wizard-generate
"Create a spec for /vacantes, login at /login with admin@example.com / password123, destination /vacantes"
→ auto-generates Platform/Vacantes/vacantes-description.md
→ asks: "Run the improvement wizard?" → yes
→ spec-wizard-improve walks through 9 sections
→ spec-wizard-pipeline shows summary and offers QA pipeline → yes
→ qa-coordinator generates tests, pauses for test-data.md
→ you fill test-data.md → confirm
→ test-execution runs and delivers the report
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

### Generate test cases only

```
Invoke: qa-coordinator
"Generate test cases only for Platform/Dashboard/dashboard-description.md"
→ dispatches test-generation → done
```

### Execute tests on already-filled test data

```
Invoke: qa-coordinator
"Execute tests for Platform/Login/login-description.md"
→ verifies test-cases.md and test-data.md exist
→ dispatches test-execution → report generated
```

---

## Traceability

Every artifact is linked:

```
{module}-description.md
    └── test-cases.md          references <<view-id>> and ${field-names} from spec
    └── test-data.md           provides concrete values per scenario
    └── test-report-{module}.md  records PASS/FAIL/BLOQUEADO per TC ID
    └── TC-*.png               screenshot evidence linked to TC IDs in the report
```

Test IDs follow the format `TC-{TYPE}-{NN}` (e.g. `TC-SMK-01`, `TC-HP-01`, `TC-001`).
