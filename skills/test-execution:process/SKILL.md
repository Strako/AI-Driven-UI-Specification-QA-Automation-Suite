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
3. **`vars.md`** — the path from `VARS_FILE`. Extract the `BASE_URL` value and any authentication credential variables (e.g. `AUTH_EMAIL`, `AUTH_PASSWORD`, or any custom variable names). These credential values are used when test preconditions require authentication.
4. **UI spec file** — the path from `SPEC_FILE` (if present). Read it to understand `<<view-id>>`, component structure, field types, and validation messages — this helps locate elements in the DOM.

---

### Step 2 — Hydrate test cases with test data

For every test case that has a matching entry in the test data file:

- Replace each `${field-name}` placeholder in Steps and Preconditions with the concrete value from the test data.
- Replace each `<<view-id>>` with the corresponding URL constructed as `BASE_URL` + route from the spec.
- Keep the original TC ID, Type, and Description unchanged.
- If a test case has **no matching test data entry** and its steps require input values, mark it as `⚠️ BLOCKED` with reason: "No test data defined for this case".

---

### Step 3 — Execute test cases

Execute each test case sequentially using the Playwright MCP tools. Follow these rules strictly.

#### 3.1 — Execution rules

- Execute **every** test case. Do not skip any without marking it BLOCKED.
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
- Name screenshots using the pattern: `{TC-ID}-{short-description}.png` (e.g. `TC-SMK-01-page-loaded.png`).
- Save all screenshots in the same directory as the test cases file.

#### 3.3 — Design Comparison execution (TC-DC type)

When executing a test case of type **Design Comparison** (ID prefix `TC-DC`):

1. **Navigate** to the page URL and take a full-page screenshot using `mcp__playwright_headed__browser_take_screenshot`.
2. **Retrieve the design reference** from the spec's `Pencil slide name / Figma frame URL` field:
   - **If it's a Figma URL** (contains `figma.com`): Use the **Figma MCP** tools to fetch the design frame. Extract the node ID from the URL and retrieve the frame's visual structure including components, layout, colors, typography, spacing, and hierarchy.
   - **If it's a Pencil slide name** (does not contain `figma.com`): Use the **Pencil MCP** tools to read the `.pen` file, locate the frame/slide by name using `batch_get` with a name pattern search, and extract its visual structure including components, layout, colors, typography, spacing, and hierarchy.
3. **Take a snapshot** of the live page DOM using `mcp__playwright_headed__browser_snapshot` to get the full accessibility tree and element structure.
4. **Compare** the design against the live implementation across these dimensions:
   - **Structure / Layout**: Component presence, order, hierarchy, positioning
   - **Typography**: Font families, sizes, weights, line heights, text colors
   - **Colors**: Background colors, border colors, accent colors, gradients
   - **Spacing**: Margins, paddings, gaps, alignment, distribution
   - **Components**: Buttons, inputs, cards, modals — shape, size, states
   - **Images / Icons**: Presence, size, position, aspect ratio
5. **Classify each discrepancy** by severity:
   - **Critical**: Component missing, completely broken, or functionally different
   - **Major**: Significant layout, size, or position differences affecting usability
   - **Minor**: Color, typography, or spacing differences not affecting functionality
   - **Cosmetic**: Barely perceptible differences (1-2px, very similar tones)
6. **Document all findings** in the Design Comparison section of the report (see Step 4 section 4.7).

> The Design Comparison test case result is classified as:
>
> - ✅ PASS — if zero critical or major discrepancies are found
> - ❌ FAIL — if any critical or major discrepancies are found
> - ⚠️ BLOCKED — if the design reference cannot be retrieved (MCP tool failure, invalid URL/name)

#### 3.4 — Result classification

Classify each test case result as:

| Status  | Emoji | Condition                                                                |
| ------- | ----- | ------------------------------------------------------------------------ |
| PASS    | ✅    | All steps completed and expected result matches observed behavior        |
| FAIL    | ❌    | One or more steps did not produce the expected result                    |
| BLOCKED | ⚠️    | Test cannot be executed due to environment, data, or tooling limitations |

For **FAIL** results, record:

- The **exact step** where the error occurred
- The **expected result** (from the test case)
- The **actual result** (what was observed)
- The **probable cause** of the failure
- The **screenshot filename** as evidence

For **BLOCKED** results, record:

- The **reason** why the test could not be executed

---

### Step 4 — Generate the execution report

After all test cases have been executed, write a report file named `test-report-{module-name}.md` in the same directory as the test cases file. Derive `{module-name}` from the spec file name or the view ID.

The report **MUST** follow this exact structure. No sections may be omitted, renamed, or restructured.

---

#### 4.1 — Header

```markdown
# Test Execution Report — {Module name}

**URL:** `{full URL from BASE_URL + route}`
**Date:** {YYYY-MM-DD}
**Executed with:** Playwright MCP — server `playwright_headed` (MCP tool, not Node.js code)

---
```

#### 4.2 — Executive Summary

A summary table with one row per test type and a TOTAL row. Calculate and display the success rate.

```markdown
## Executive Summary

| Category          | Total | ✅ Passed | ❌ Failed | ⚠️ Blocked |
| ----------------- | ----- | --------- | --------- | ---------- |
| Smoke Tests       | N     | N         | N         | N          |
| Happy Path        | N     | N         | N         | N          |
| Functional Tests  | N     | N         | N         | N          |
| Edge Cases        | N     | N         | N         | N          |
| Exploratory Tests | N     | N         | N         | N          |
| Design Comparison | N     | N         | N         | N          |
| **TOTAL**         | **N** | **N**     | **N**     | **N**      |

**Success rate: X/Y (Z%)**

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
## DESIGN COMPARISON (include only if a TC-DC test case exists)
```

Each section must:

- Show a summary line: `(X/Y ✅)` if all pass, or `(X/Y — N failed)` if any failed.
- Include a table with columns: `| ID | Description | Result | Detail |`
- The **Detail** column must explain what was validated and what occurred — clear, concise, and verifiable.

```markdown
## SMOKE TESTS (X/Y ✅)

| ID        | Description | Result  | Detail                         |
| --------- | ----------- | ------- | ------------------------------ |
| TC-SMK-01 | Description | ✅ PASS | What was verified and observed |
```

#### 4.4 — Failure Details

Include **only** if there are failed tests:

```markdown
## Failure Details

### {ID} — {Test name}

**Step where error occurred:** {Specific step}
**Expected result:** {Expected behavior}
**Actual result:** {What actually happened}
**Failure reason:** {Probable or technical cause}
**Evidence:** {Screenshot filename}
```

#### 4.5 — Blocked Tests Details

Include **only** if there are blocked tests:

```markdown
## Blocked Tests Details

### {ID} — {Test name}

**Reason:** {Clear explanation of why the test could not be executed}
```

#### 4.6 — Captured Screenshots

Always include — list all captured screenshots:

```markdown
## Captured Screenshots

| File           | Description                              |
| -------------- | ---------------------------------------- |
| `filename.png` | Description of what the screenshot shows |
```

#### 4.7 — Design Comparison (include only if a TC-DC test case was executed)

```markdown
## DESIGN COMPARISON

### Design Reference

- **Source**: {Figma frame URL or Pencil slide name}
- **Comparison date**: {YYYY-MM-DD}

### Discrepancy Summary

| Category           | Discrepancies | Critical Severity | Major Severity | Minor Severity | Cosmetic |
| ------------------ | ------------- | ----------------- | -------------- | -------------- | -------- |
| Structure / Layout | N             | N                 | N              | N              | N        |
| Typography         | N             | N                 | N              | N              | N        |
| Colors             | N             | N                 | N              | N              | N        |
| Spacing            | N             | N                 | N              | N              | N        |
| Components         | N             | N                 | N              | N              | N        |
| Images / Icons     | N             | N                 | N              | N              | N        |
| **TOTAL**          | **N**         | **N**             | **N**          | **N**          | **N**    |

### Discrepancy Details

#### {Category} — {Affected element}

- **Severity**: Critical | Major | Minor | Cosmetic
- **In the design**: {description of how it looks in the design}
- **In the implementation**: {description of how it looks on the web}
- **Affected component**: `<<component-id>>` or specific element
- **Evidence**: {screenshot filename}
```

Repeat the "Discrepancy Details" block for each discrepancy found. If no discrepancies are found, write:

```markdown
### Discrepancy Details

No significant discrepancies were found between the design and the implementation.
```

---

### Step 5 — Consistency rules

The report **MUST** comply with these rules:

- Maintain titles, subtitles, and separators (`---`) exactly as shown.
- Use Markdown tables with correct alignment.
- Use status emojis consistently: ✅ PASS, ❌ FAIL, ⚠️ BLOCKED.
- Keep section names in UPPERCASE where specified.
- Include aggregate metrics (totals, success rate).
- Write in **technical English**.
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
