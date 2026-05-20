# Skill: test-execution:process

## Test Execution

You are acting as a QA automation engineer. Execute every test case defined in the `TEST_CASES_FILE` against the live application using **Playwright MCP** — specifically the `playwright_headed` MCP server configured in `.mcp.json` — then produce a structured execution report.

---

### Step 0 — Playwright MCP server

> ⛔ **CRITICAL — Playwright MCP only. Never write code.**
> All browser interactions MUST be performed exclusively through **Playwright MCP tool calls** using the prefix `mcp__playwright_headed__`.
> NEVER write or run Node.js/JavaScript Playwright code (`require('playwright')`, `@playwright/test`, `page.goto()`, `page.click()`, `chromium.launch()`, `npx playwright test`, etc.).
> NEVER use `Bash` to run Playwright scripts, CLI commands, or any programmatic browser automation.
> The tools below are MCP tool invocations — call them directly as tools, not as code.

Tool prefix for every browser call: **`mcp__playwright_headed__`**
Never use `mcp__playwright__` (headless). Never mix prefixes mid-execution.

---

### Step 1 — Read required files

Read the following files **in order** before executing anything:

1. **Test cases file** — the path from `TEST_CASES_FILE`. Parse every test case extracting: ID, Type, Description, Preconditions, Steps, and Expected Result.
2. **Test data file** — the path from `TEST_DATA_FILE`. For each TC ID, extract the concrete values that replace `${field-name}` placeholders.
3. **`vars.md`** — the path from `VARS_FILE`. Extract the `BASE_URL` value.
4. **UI spec file** — the path from `SPEC_FILE` (if present). Read it to understand `<<view-id>>`, component structure, field types, and validation messages — this helps locate elements in the DOM.

---

### Step 2 — Hydrate test cases with test data

For every test case that has a matching entry in the test data file:

- Replace each `${field-name}` placeholder in Steps and Preconditions with the concrete value from the test data.
- Replace each `<<view-id>>` with the corresponding URL constructed as `BASE_URL` + route from the spec.
- Keep the original TC ID, Type, and Description unchanged.
- If a test case has **no matching test data entry** and its steps require input values, mark it as `⚠️ BLOQUEADO` with reason: "Sin datos de prueba definidos para este caso".

---

### Step 3 — Execute test cases

Execute each test case sequentially using the Playwright MCP tools. Follow these rules strictly.

#### 3.1 — Execution rules

- Execute **every** test case. Do not skip any without marking it BLOQUEADO.
- Follow the steps **exactly** as defined. Do not modify, assume, or extend scenarios.
- Before each test case, navigate to the required URL from the preconditions using `BASE_URL` + route.
- For each step, call the appropriate Playwright MCP tool (prefix: `mcp__playwright_headed__`):
  - **Navigate**: `mcp__playwright_headed__browser_navigate`
  - **Get DOM state / element refs**: `mcp__playwright_headed__browser_snapshot` — always call this before click/type to identify the current element `ref=` values
  - **Click**: `mcp__playwright_headed__browser_click` — use the `ref=` from the snapshot output
  - **Type in input / fill field**: `mcp__playwright_headed__browser_type`
  - **Select dropdown option**: `mcp__playwright_headed__browser_select_option`
  - **Press a key**: `mcp__playwright_headed__browser_press_key`
  - **Hover**: `mcp__playwright_headed__browser_hover`
  - **Screenshot for evidence**: `mcp__playwright_headed__browser_take_screenshot`
  - **Resize viewport**: `mcp__playwright_headed__browser_resize`
  - **Wait for condition or timeout**: `mcp__playwright_headed__browser_wait_for`
  - **Evaluate JS**: `mcp__playwright_headed__browser_evaluate`

#### 3.2 — Evidence capture

- Take a **screenshot** at the end of every test case execution using `mcp__playwright_headed__browser_take_screenshot`.
- For **failed** test cases, take an additional screenshot at the exact step where the failure occurred.
- Name screenshots using the pattern: `{TC-ID}-{short-description}.png` (e.g. `TC-SMK-01-pagina-cargada.png`).
- Save all screenshots in the same directory as the test cases file.

#### 3.3 — Result classification

Classify each test case result as:

| Status | Emoji | Condition |
|--------|-------|-----------|
| PASS | ✅ | All steps completed and expected result matches observed behavior |
| FAIL | ❌ | One or more steps did not produce the expected result |
| BLOQUEADO | ⚠️ | Test cannot be executed due to environment, data, or tooling limitations |

For **FAIL** results, record:
- The **exact step** where the error occurred
- The **expected result** (from the test case)
- The **actual result** (what was observed)
- The **probable cause** of the failure
- The **screenshot filename** as evidence

For **BLOQUEADO** results, record:
- The **reason** why the test could not be executed

---

### Step 4 — Generate the execution report

After all test cases have been executed, write a report file named `test-report-{module-name}.md` in the same directory as the test cases file. Derive `{module-name}` from the spec file name or the view ID.

The report **MUST** follow this exact structure. No sections may be omitted, renamed, or restructured.

---

#### 4.1 — Header

```markdown
# Reporte de Ejecución de Tests — {Nombre del módulo}

**URL:** `{full URL from BASE_URL + route}`
**Fecha:** {YYYY-MM-DD}
**Ejecutado con:** Playwright MCP — servidor `playwright_headed` (herramienta MCP, no código Node.js)

---
```

#### 4.2 — Resumen Ejecutivo

A summary table with one row per test type and a TOTAL row. Calculate and display the success rate.

```markdown
## Resumen Ejecutivo

| Categoría         | Total | ✅ Exitosos | ❌ Fallidos | ⚠️ Bloqueados |
| ----------------- | ----- | ----------- | ----------- | ------------- |
| Smoke Tests       | N     | N           | N           | N             |
| Happy Path        | N     | N           | N           | N             |
| Functional Tests  | N     | N           | N           | N             |
| Edge Cases        | N     | N           | N           | N             |
| Exploratory Tests | N     | N           | N           | N             |
| **TOTAL**         | **N** | **N**       | **N**       | **N**         |

**Tasa de éxito: X/Y (Z%)**

---
```

#### 4.3 — Test sections

Always create the following five sections, even if all tests pass:

```
## SMOKE TESTS
## HAPPY PATH
## FUNCTIONAL TESTS
## EDGE CASES
## EXPLORATORY TESTS
```

Each section must:
- Show a summary line: `(X/Y ✅)` if all pass, or `(X/Y — N fallidos)` if any failed.
- Include a table with columns: `| ID | Descripción | Resultado | Detalle |`
- The **Detalle** column must explain what was validated and what occurred — clear, concise, and verifiable.

```markdown
## SMOKE TESTS (X/Y ✅)

| ID        | Descripción | Resultado | Detalle                        |
| --------- | ----------- | --------- | ------------------------------ |
| TC-SMK-01 | Description | ✅ PASS   | What was verified and observed |
```

#### 4.4 — Detalle de Fallos

Include **only** if there are failed tests:

```markdown
## Detalle de Fallos

### {ID} — {Nombre del test}

**Paso donde ocurrió el error:** {Specific step}
**Resultado esperado:** {Expected behavior}
**Resultado obtenido:** {What actually happened}
**Motivo del fallo:** {Probable or technical cause}
**Evidencia:** {Screenshot filename}
```

#### 4.5 — Detalle de Tests Bloqueados

Include **only** if there are blocked tests:

```markdown
## Detalle de Tests Bloqueados

### {ID} — {Nombre del test}

**Razón:** {Clear explanation of why the test could not be executed}
```

#### 4.6 — Screenshots Capturados

Always include — list all captured screenshots:

```markdown
## Screenshots Capturados

| Archivo        | Descripción                              |
| -------------- | ---------------------------------------- |
| `filename.png` | Description of what the screenshot shows |
```

---

### Step 5 — Consistency rules

The report **MUST** comply with these rules:
- Maintain titles, subtitles, and separators (`---`) exactly as shown.
- Use Markdown tables with correct alignment.
- Use status emojis consistently: ✅ PASS, ❌ FAIL, ⚠️ BLOQUEADO.
- Keep section names in UPPERCASE where specified.
- Include aggregate metrics (totals, success rate).
- Write in **technical Spanish**.
- TC IDs must follow the format from the test cases file (e.g. `TC-SMK-01`, `TC-HP-01`, `TC-001`).
- Descriptions must be clear, concise, and verifiable.
- Details must explain what was validated and what occurred.
- Use present tense verbs.
- Do not mix languages.
- Do NOT change section names, structure, summarize excessively, omit tables, or use free format.

---

### Step 6 — Report completion

Once the report is written, output the structured `---EXECUTION-COMPLETE---` block as defined in the agent instructions, then provide a human-readable summary:
- Path to the generated report file.
- Total test cases executed, broken down by result (✅, ❌, ⚠️).
- Success rate percentage.
- Number of screenshots captured.
- Key findings or issues discovered during execution (if any).
