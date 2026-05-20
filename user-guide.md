# User Guide — QA Automation Suite

Step-by-step walkthrough from a live page URL to a complete test execution report.

---

## Before You Start

Make sure `vars.md` at the project root has your app's base URL:

```
BASE_URL = https://www.google.com
```

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
Login is at /login — credentials: admin@dacodes.com / mypassword123
Destination after login: /dashboard
Module name: dashboard
```

Or just provide the minimum and the agent will ask for the rest:

```
Create a spec for /dashboard
```

### Inputs collected

| Input               | Required | Description                                                  |
| ------------------- | -------- | ------------------------------------------------------------ |
| `PAGE_URL`          | Yes      | Route or full URL of the page to analyze (e.g. `/dashboard`) |
| `MODULE_NAME`       | No       | Short kebab-case name — derived from URL if omitted          |
| `AUTH_REQUIRED`     | No       | Whether the page needs authentication first                  |
| `LOGIN_ROUTE`       | If auth  | Route of the login page (e.g. `/login`)                      |
| `AUTH_EMAIL`        | If auth  | Login email or username                                      |
| `AUTH_PASSWORD`     | If auth  | Password                                                     |
| `DESTINATION_ROUTE` | If auth  | Page to analyze after login (defaults to `PAGE_URL`)         |
| `OUTPUT_DIR`        | No       | Where to save (default: `Platform/{ModuleName}/`)            |

> All routes starting with `/` are automatically resolved as `BASE_URL + route` using `vars.md`.

### What happens

After you confirm the inputs, the agent:

1. **Authenticates** (if required) — navigates to login, fills credentials, submits
2. **Navigates** to the target page
3. **Captures** a screenshot (`{module}-analysis.png`) and the full accessibility tree
4. **Scrolls** through the page and interacts with tabs/expandable sections
5. **Analyzes** the DOM to identify components, fields, actions, and states
6. **Generates** the complete spec following `TEMPLATE.md` format
7. **Saves** to `Platform/{ModuleName}/{module}-description.md`

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
## [TC-SMK-01] Vista del dashboard carga correctamente

- **Type**: Smoke
- **Preconditions**: El usuario está autenticado y navega a
  https://www.google.com/dashboard
- **Steps**:
  1. Navegar a `BASE_URL + /dashboard`
  2. Verificar que `<<stats-panel-...>>` es visible
  3. Verificar que `<<jobs-table-...>>` es visible
- **Expected Result**: Todos los componentes principales son visibles sin errores
```

Coverage generated: **Happy Path · Smoke · Functional · Edge Cases · Exploratory**

**`test-data.md`** — empty template organized by scenario

```markdown
# Test Data — <<dashboard-3f2c1a9b-...>>

## [TC-HP-01] Búsqueda de empleos funciona correctamente

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
## [TC-HP-01] Búsqueda de empleos funciona correctamente

### <<dashboard-3f2c1a9b-...>>

- ${jobs-search}: desarrollador
- ${jobs-status-filter}: published

## [TC-FN-03] Filtro por estado muestra borradores

### <<dashboard-3f2c1a9b-...>>

- ${jobs-status-filter}: draft

## [TC-EC-01] Búsqueda con término sin resultados

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

## Step 5 — Test Execution

The `test-execution` agent works through every test case sequentially:

1. Reads `test-cases.md`, `test-data.md`, `vars.md`, and the spec file
2. **Hydrates** each test case — replaces every `${field-name}` with the concrete value you filled in
3. For each test case:
   - `browser_navigate` → goes to the precondition URL
   - `browser_snapshot` → reads the DOM, gets element `ref=` values
   - `browser_type` → fills inputs
   - `browser_click` → clicks buttons using their `ref=`
   - `browser_take_screenshot` → captures evidence
4. Classifies each result: **✅ PASS · ❌ FAIL · ⚠️ BLOQUEADO**
5. Writes `Platform/Dashboard/test-report-dashboard.md`

### Result classification

| Status       | When                                                                        |
| ------------ | --------------------------------------------------------------------------- |
| ✅ PASS      | All steps completed and the expected result matched observed behavior       |
| ❌ FAIL      | One or more steps did not produce the expected result                       |
| ⚠️ BLOQUEADO | Test could not run — missing data, environment issue, or tooling limitation |

### What the report looks like

```markdown
# Reporte de Ejecución de Tests — Dashboard

**URL:** `https://www.google.com/dashboard`
**Fecha:** 2026-05-20
**Ejecutado con:** Playwright MCP — servidor `playwright_headed`

---

## Resumen Ejecutivo

| Categoría         | Total  | ✅ Exitosos | ❌ Fallidos | ⚠️ Bloqueados |
| ----------------- | ------ | ----------- | ----------- | ------------- |
| Smoke Tests       | 3      | 3           | 0           | 0             |
| Happy Path        | 2      | 2           | 0           | 0             |
| Functional Tests  | 9      | 7           | 2           | 0             |
| Edge Cases        | 6      | 5           | 0           | 1             |
| Exploratory Tests | 4      | 3           | 1           | 0             |
| **TOTAL**         | **24** | **20**      | **3**       | **1**         |

**Tasa de éxito: 20/24 (83%)**

---

## SMOKE TESTS (3/3 ✅) ...

## HAPPY PATH (2/2 ✅) ...

## FUNCTIONAL TESTS (7/9 — 2 fallidos) ...

## EDGE CASES (5/6 — 1 bloqueado) ...

## EXPLORATORY TESTS (3/4 — 1 fallido) ...

## Detalle de Fallos

### TC-FN-05 — Filtro por estado muestra solo borradores

**Paso donde ocurrió el error:** Paso 3
**Resultado esperado:** Tabla muestra únicamente empleos con estado draft
**Resultado obtenido:** Tabla mostró empleos en todos los estados
**Motivo del fallo:** El filtro de estado no aplica el parámetro correctamente
**Evidencia:** TC-FN-05-filtro-estado-fallo.png

## Screenshots Capturados

| Archivo                            | Descripción                      |
| ---------------------------------- | -------------------------------- |
| `TC-SMK-01-pagina-cargada.png`     | Vista principal del dashboard    |
| `TC-HP-01-busqueda-exitosa.png`    | Resultados de búsqueda filtrados |
| `TC-FN-05-filtro-estado-fallo.png` | Fallo en filtro de estado        |
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

| You want to…                           | Agent                  | Message                                                                      |
| -------------------------------------- | ---------------------- | ---------------------------------------------------------------------------- |
| Auto-generate a spec from a live page  | `spec-wizard-generate` | `"Create a spec for /dashboard, login at /login with user@x.com / pass123"`  |
| Improve an existing spec interactively | `spec-wizard-improve`  | `"Improve Platform/Dashboard/dashboard-description.md"`                      |
| See spec summary + offer pipeline      | `spec-wizard-pipeline` | `"Summarize Platform/Dashboard/dashboard-description.md"`                    |
| Full pipeline on an existing spec      | `qa-coordinator`       | `"Run the full QA pipeline for Platform/Dashboard/dashboard-description.md"` |
| Generate test cases only               | `qa-coordinator`       | `"Generate test cases only for Platform/Dashboard/dashboard-description.md"` |
| Execute already-filled tests           | `qa-coordinator`       | `"Execute tests for Platform/Dashboard/dashboard-description.md"`            |
| Create spec without login              | `spec-wizard-generate` | `"Create a spec for /jobs, module name vacantes"`                            |
| Use legacy wizard (full interview)     | `spec-wizard`          | `"Create a spec for /dashboard"`                                             |

---

## Tips

- **All output goes to `Platform/`** — every module gets its own subfolder under `Platform/`. This keeps specs, test cases, and reports organized by screen.

- **Headed mode only** — the system always uses the headed Playwright browser (`playwright_headed`). You can watch the browser during execution, which is useful when debugging failures.

- **Re-running after a fix** — invoke `qa-coordinator` with "Execute tests for …" (execute-only mode). No need to regenerate test cases unless the spec changed.

- **Updating the spec** — run `spec-wizard-improve` on the existing file. Then re-run `qa-coordinator` to regenerate test cases from the updated spec.

- **Multiple modules** — each module lives in its own `Platform/{ModuleName}/` folder. Run the pipeline on any of them independently.

- **Changing the base URL** — edit `vars.md`. All agents pick it up automatically on their next run.

- **Pipeline state** — the `.claude/.pipeline-state` file tracks where you are in the pipeline. If something gets stuck, you can delete this file to reset state and start fresh.

- **No programmatic Playwright** — the system never writes or runs Playwright code. All browser automation happens through MCP tool calls. This means no `node_modules`, no test scripts, no `npx playwright` commands.
