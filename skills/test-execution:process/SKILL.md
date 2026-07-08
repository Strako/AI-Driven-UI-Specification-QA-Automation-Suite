# Skill: test-execution:process

## Test Execution

You are acting as a QA automation engineer. Execute every test case defined in the `TEST_CASES_FILE` against the live application using **Playwright MCP** — specifically the `playwright_headed` MCP server configured in `.mcp.json` — then produce a structured execution report.

---

### Step 0 — Playwright MCP server

> ⛔ **CRITICAL — Playwright MCP only. Never write code.**
> All browser interactions MUST be performed exclusively through **Playwright MCP tool calls** using the prefix `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__`.
> NEVER write or run Node.js/JavaScript Playwright code (`require('playwright')`, `@playwright/test`, `page.goto()`, `page.click()`, `chromium.launch()`, `npx playwright test`, etc.).
> NEVER use `Bash` to run Playwright scripts, CLI commands, or any programmatic browser automation.
> The tools below are MCP tool invocations — call them directly as tools, not as code.

Tool prefix for every browser call: **`mcp__plugin_AI-Driven-UI-Specification_playwright_headed__`**
Never use `mcp__playwright__` (headless). Never mix prefixes mid-execution.

---

### Step 1 — Read required files

Read the following files **in order** before executing anything:

1. **Test cases file** — the path from `TEST_CASES_FILE`. Parse every test case extracting: ID, Type, Severity, Description, Preconditions, Steps, and Expected Result.
2. **Test data file** — the path from `TEST_DATA_FILE`. For each TC ID, extract the concrete values that replace `${field-name}` placeholders.
3. **`vars.md`** — the path from `VARS_FILE`. Extract the `BASE_URL` value and any authentication credential variables (e.g. `AUTH_EMAIL`, `AUTH_PASSWORD`, or any custom variable names). `BASE_URL` is used to resolve every `<<view-id>>` and every literal `{{BASE_URL}}` token found in the test cases into a real URL — this is the only step in the whole pipeline where `BASE_URL` is resolved to its concrete value, which is what lets the same test cases run against any environment just by editing `vars.md`. Credential values are used when test preconditions require authentication.
4. **UI spec file** — the path from `SPEC_FILE` (if present). Read it to understand `<<view-id>>`, component structure, field types, and validation messages — this helps locate elements in the DOM.
5. **`EXECUTION_LEVEL`** — from your input contract, not a file. Defaults to `3` (All) if not provided. Used in Step 2a to decide which test cases actually run.

---

### Step 1a — Resolve the persistent test identity (AUTH_EMAIL / AUTH_PASSWORD)

Some test cases create an account (signup/registration flows). This suite reuses **one persistent test identity** across every run instead of signing up fresh each time. The identity format and Yopmail mechanics are defined once in `skills/shared:account-identity/SKILL.md` — this step only adds the test-execution-specific decision logic around it (which test case drives creation, and how to classify the others).

1. **Detect placeholder vs. real values.** Follow `skills/shared:account-identity/SKILL.md` Step A for `AUTH_EMAIL` / `AUTH_PASSWORD` (placeholders are the literal seed strings `your-login-email@example.com` and `your-login-password`).

2. **If real values are already persisted** (Step A found them "already a real value"):
   - Use `AUTH_EMAIL` / `AUTH_PASSWORD` for every `{{AUTH_EMAIL}}` / `{{AUTH_PASSWORD}}` token and for every precondition that requires an existing/logged-in account.
   - Any test case whose purpose is to **create that same account** (Type/Description/Steps mention signup, registration, "create account") is marked `⚠️ BLOCKED` with reason: `"Persistent test account already exists (AUTH_EMAIL in vars.md) — skipping re-creation to avoid a duplicate-account error. Restore the placeholder values in vars.md to force recreation."` Do not attempt the signup submission in this case — most apps reject a duplicate registration, which would otherwise read as a false failure.

3. **If placeholders are still present:**
   - Scan all test cases for one whose Type/Description/Steps indicate account creation (keywords: "sign up", "signup", "register", "registration", "create account"). At most one such test case drives identity creation per run.
   - **If found**, generate the persistent identity before executing that test case:
     - Follow `skills/shared:account-identity/SKILL.md` Step B to generate `AUTH_EMAIL` = `qa-{random}@yopmail.com` and `AUTH_PASSWORD` = `Qa!{random}9` from the same random suffix.
     - Use these generated values to hydrate the signup test case's email/password fields (overriding an empty test-data.md entry for just this test case — this is the one exception to the "no test data → BLOCKED" rule in Step 2).
     - Execute the signup flow (shared skill Step C). If it requires OTP/email confirmation, run the Yopmail procedure (shared skill Step D / this skill's Step 3.1a) using this `AUTH_EMAIL`.
     - **Only if the test case reaches ✅ PASS** (including confirmation, if required): follow shared skill Step E to persist `AUTH_EMAIL` and `AUTH_PASSWORD` into `vars.md`. This is the only step that ever writes to `vars.md`.
     - If the signup test case does not pass, leave the placeholders untouched so the next run retries with a fresh identity.
   - **If not found** (no account-creation test case in this run): any test case whose precondition requires an existing/logged-in account is marked `⚠️ BLOCKED` with reason: `"No persisted credentials in vars.md (still placeholders) and no account-creation test case in this run to generate them."`

---

### Step 2 — Hydrate test cases with test data

For every test case:

- Replace each `${field-name}` placeholder in Steps and Preconditions with the concrete value from the test data (for test cases that have a matching entry in the test data file).
- Replace each `<<view-id>>` with the corresponding URL, constructed as the `BASE_URL` value read from `vars.md` + that view's Route from the spec.
- Replace every literal `{{VARIABLE_NAME}}` token (e.g. `{{BASE_URL}}`, `{{AUTH_EMAIL}}`, `{{AUTH_PASSWORD}}`, or any custom variable) with the corresponding value read from `vars.md` in Step 1 — using the resolved identity from Step 1a for `{{AUTH_EMAIL}}` / `{{AUTH_PASSWORD}}`.
- Keep the original TC ID, Type, Severity, and Description unchanged.
- If a test case has **no matching test data entry** and its steps require input values, mark it as `⚠️ BLOCKED` with reason: "No test data defined for this case".

---

### Step 2a — Filter by execution level

Before executing anything, partition all hydrated test cases by `Severity` according to `EXECUTION_LEVEL` (Step 1):

| `EXECUTION_LEVEL` | Test cases that run |
| --- | --- |
| `1` | Severity = Critical only |
| `2` | Severity = Critical or Mid |
| `3` (default) | Every test case, regardless of severity |

Every test case excluded by this filter is marked `⏭ SKIPPED` with reason `"Below configured execution level ({EXECUTION_LEVEL})"` and is **never executed** — no navigation, no screenshot, no Playwright MCP calls of any kind for it, exactly like a `⚠️ BLOCKED` case today. This filtering happens once, before Step 3 begins, and applies independently of test data availability — a test case can be `⏭ SKIPPED` even if it would otherwise have had valid test data.

---

### Step 3 — Execute test cases

Execute each test case sequentially using the Playwright MCP tools. Follow these rules strictly.

#### 3.0 — Timestamps

There is no clock available outside the browser page (no `Bash`, no `date` command). Every timestamp used in evidence filenames and in the report **must** be obtained by calling `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate` with a JS expression evaluated in the page context. Use these two exact forms:

- **Filename timestamp** — compact, filesystem-safe, no spaces or colons:
  ```js
  () => { const d = new Date(); const p = n => String(n).padStart(2, '0'); return `${d.getFullYear()}${p(d.getMonth()+1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`; }
  ```
  Produces e.g. `20260703-143205`.

- **Report timestamp** — human-readable, used inside the report:
  ```js
  () => { const d = new Date(); const p = n => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`; }
  ```
  Produces e.g. `2026-07-03 14:32:05`.

Capture two **report timestamps**:

- **`EXECUTION_STARTED`** — immediately before executing the first test case.
- **`EXECUTION_COMPLETED`** — immediately after executing the last test case (before writing the report).

Both values are used in Step 4 (report header and Executive Summary).

#### 3.1 — Execution rules

- Execute **every** test case that was not filtered out in Step 2a. Do not skip any of the remaining ones without marking it BLOCKED.
- Follow the steps **exactly** as defined. Do not modify, assume, or extend scenarios.
- Before each test case, navigate to the required URL already resolved in Step 2 (from the `<<view-id>>` or `{{BASE_URL}}` tokens in the preconditions).
- For each step, call the appropriate Playwright MCP tool (prefix: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__`):
  - **Navigate**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_navigate`
  - **Get DOM state / element refs**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_snapshot` — always call this before click/type to identify the current element `ref=` values
  - **Click**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_click` — use the `ref=` from the snapshot output
  - **Type in input / fill field**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_type`
  - **Select dropdown option**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_select_option`
  - **Press a key**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_press_key`
  - **Hover**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_hover`
  - **Screenshot for evidence**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_take_screenshot`
  - **Resize viewport**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_resize`
  - **Wait for condition or timeout**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_wait_for`
  - **Evaluate JS**: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate`

#### 3.1a — Email verification via Yopmail (OTP / confirmation codes / confirmation links)

Whenever a step or expected result requires checking an OTP, verification code, or confirmation email (e.g. after signup, or a 2FA/reset flow), verify it through **Yopmail** — never assume delivery, never fabricate a code. Follow `skills/shared:account-identity/SKILL.md` Step D exactly; the mapping to this skill's concepts is:

- "the target email" = the resolved `{{AUTH_EMAIL}}` (Step 1a), otherwise whatever `${field-name}` email value the test case used earlier in its own steps.
- "report failure using the caller's own convention" = mark the test case `⚠️ BLOCKED` with reason `"Yopmail displayed an unexpected inbox address and could not be corrected."`
- "continue the caller's flow" = continue the test case: type the code into the app's input and submit, or — if a link was clicked — proceed per the expected result (e.g. reload/navigate, since confirmation already completed server-side).
- Close the Yopmail tab before moving to the next test case.

---

#### 3.2 — Evidence capture

> ⛔ **Evidence is mandatory for every test case regardless of outcome.** Capture a screenshot whether the result is ✅ PASS or ❌ FAIL. Never skip evidence capture because a test passed — a passing result without a screenshot is not verifiable.

- Take a **screenshot** at the end of every test case execution using `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_take_screenshot`:
  - For ✅ **PASS** results, this screenshot is the proof of the successful end state.
  - For ❌ **FAIL** results, this screenshot is the proof of the failing end state.
- For **failed** test cases, take an additional screenshot at the exact step where the failure occurred (obtain a fresh filename timestamp for it — do not reuse the end-of-test one).
- ⚠️ **BLOCKED** test cases have no evidence to capture, since they never execute — record the reason instead (Step 3.4).
- Before capturing each screenshot, obtain a **filename timestamp** as defined in Step 3.0.
- Name screenshots using the pattern: `{TC-ID}-{short-description}-{filename-timestamp}.png` (e.g. `TC-SMK-01-page-loaded-20260703-143205.png`, and for a failure step `TC-SMK-01-failure-step-20260703-143207.png`).
- Save all screenshots inside an **`evidences/`** subfolder of the test cases file's directory — never directly in the module folder. Pass the `filename` parameter of `browser_take_screenshot` as the full path `{absolute directory of the test cases file}/evidences/{TC-ID}-{short-description}-{filename-timestamp}.png`. This subfolder is created automatically by the `pipeline-on-tests-generated.sh` hook when `test-cases.md` is written, so it already exists by the time execution starts — do not attempt to create it yourself (this agent has no `Bash`/mkdir access).
- Immediately after capturing the end-of-test screenshot (whether PASS or FAIL), obtain a **report timestamp** as defined in Step 3.0 and record it as this test case's own `TC_TIMESTAMP` — every executed test case gets one, distinct from the two overall `EXECUTION_STARTED`/`EXECUTION_COMPLETED` timestamps. `⚠️ BLOCKED` and `⏭ SKIPPED` cases have no `TC_TIMESTAMP` since they never execute.

#### 3.3 — Design Comparison execution (TC-DC type)

When executing a test case of type **Design Comparison** (ID prefix `TC-DC`):

1. **Navigate** to the page URL and take a full-page screenshot using `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_take_screenshot`, named and saved using the same `{TC-ID}-{short-description}-{filename-timestamp}.png` pattern and `evidences/` subfolder from Step 3.2 (filename timestamp obtained as defined in Step 3.0).
2. **Retrieve the design reference** from the spec's `Pencil slide name / Figma frame URL` field:
   - **If it's a Figma URL** (contains `figma.com`): Use the **Figma MCP** tools to fetch the design frame. Extract the node ID from the URL and retrieve the frame's visual structure including components, layout, colors, typography, spacing, and hierarchy.
   - **If it's a Pencil slide name** (does not contain `figma.com`): Use the **Pencil MCP** tools to read the `.pen` file, locate the frame/slide by name using `batch_get` with a name pattern search, and extract its visual structure including components, layout, colors, typography, spacing, and hierarchy.
3. **Take a snapshot** of the live page DOM using `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_snapshot` to get the full accessibility tree and element structure.
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
| SKIPPED | ⏭    | Excluded by the configured `EXECUTION_LEVEL` (Step 2a) — never executed  |

For **every executed test case** (✅ PASS or ❌ FAIL), record — both go directly into that test case's row in its section table (Step 4.3):

- Its **`TC_TIMESTAMP`** (Step 3.2)
- Its end-of-test **screenshot filename** as evidence (`evidences/{filename}`)

For **FAIL** results, additionally record (for Failure Details, Step 4.4):

- The **exact step** where the error occurred
- The **expected result** (from the test case)
- The **actual result** (what was observed)
- The **probable cause** of the failure
- The **failure-step screenshot filename** as evidence (distinct from the end-of-test one above)

For **BLOCKED** results, record:

- The **reason** why the test could not be executed

For **SKIPPED** results, record:

- The **reason**: `"Below configured execution level ({EXECUTION_LEVEL})"`

---

### Step 4 — Generate the execution report

After all test cases have been executed, write a report file named `test-report-{module-name}.md` in the same directory as the test cases file. Derive `{module-name}` from the spec file name or the view ID.

The report **MUST** follow this exact structure. No sections may be omitted, renamed, or restructured.

---

#### 4.1 — Header

```markdown
# Test Execution Report — {Module name}

**URL:** `{full URL from BASE_URL + route}`
**Date:** {EXECUTION_STARTED report timestamp, e.g. 2026-07-03 14:32:05}
**Executed with:** Playwright MCP — server `playwright_headed` (MCP tool, not Node.js code)

---
```

#### 4.2 — Executive Summary

A summary table with one row per test type and a TOTAL row. Calculate and display the success rate over **executed** test cases only (Total minus Skipped) — a `⏭ SKIPPED` case was never run, so it must not count against the success rate either way. Always include the execution timestamps captured in Step 3.0 and the `EXECUTION_LEVEL` used.

```markdown
## Executive Summary

**Execution started:** {EXECUTION_STARTED report timestamp}
**Execution completed:** {EXECUTION_COMPLETED report timestamp}
**Execution level:** {1 — Critical only / 2 — Critical + Mid / 3 — All}

| Category          | Total | ✅ Passed | ❌ Failed | ⚠️ Blocked | ⏭ Skipped |
| ----------------- | ----- | --------- | --------- | ---------- | ---------- |
| Smoke Tests       | N     | N         | N         | N          | N          |
| Happy Path        | N     | N         | N         | N          | N          |
| Functional Tests  | N     | N         | N         | N          | N          |
| Edge Cases        | N     | N         | N         | N          | N          |
| Exploratory Tests | N     | N         | N         | N          | N          |
| Design Comparison | N     | N         | N         | N          | N          |
| **TOTAL**         | **N** | **N**     | **N**     | **N**      | **N**      |

**Success rate: X/Y (Z%)** — Y excludes skipped test cases

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

- Show a summary line: `(X/Y ✅)` if all executed tests pass, `(X/Y — N failed)` if any failed, appending `, Z ⏭ skipped` whenever this section has any skipped test case — e.g. `(X/Y ✅, Z ⏭ skipped)`. `Y` here is the executed count (Total minus Skipped for this section).
- Include a table with columns: `| ID | Description | Result | Timestamp | Evidence | Detail |`
- The **Timestamp** column holds that test case's own `TC_TIMESTAMP` (Step 3.2/3.4) for an executed (✅/❌) row, or `—` for `⚠️ BLOCKED` / `⏭ SKIPPED` rows (they never execute, so they have none).
- The **Evidence** column holds the end-of-test screenshot's path relative to the test cases file's directory (always `evidences/{filename}`, per Step 3.2) for an executed row, or `—` for `⚠️ BLOCKED` / `⏭ SKIPPED` rows. For a ❌ FAIL row, this is the end-of-test screenshot specifically — the additional failure-step screenshot is referenced separately in Failure Details (4.4), not here.
- The **Detail** column must explain what was validated and what occurred — clear, concise, and verifiable. For a `⏭ SKIPPED` row, the Detail column states the reason from Step 3.4.

```markdown
## SMOKE TESTS (X/Y ✅, Z ⏭ skipped)

| ID        | Description | Result     | Timestamp           | Evidence                                    | Detail                                |
| --------- | ----------- | ---------- | -------------------- | -------------------------------------------- | -------------------------------------- |
| TC-SMK-01 | Description | ✅ PASS    | 2026-07-03 14:32:05 | `evidences/TC-SMK-01-page-loaded-20260703-143205.png` | What was verified and observed        |
| TC-SMK-02 | Description | ⏭ SKIPPED | —                     | —                                             | Below configured execution level (1)  |
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
**Evidence:** {Screenshot path relative to the test cases file's directory, e.g. `evidences/TC-SMK-01-failure-step-20260703-143207.png`}
```

#### 4.5 — Blocked Tests Details

Include **only** if there are blocked tests:

```markdown
## Blocked Tests Details

### {ID} — {Test name}

**Reason:** {Clear explanation of why the test could not be executed}
```

#### 4.6 — Skipped Tests Details

Include **only** if any test case was skipped (`EXECUTION_LEVEL` < 3 excluded it):

```markdown
## Skipped Tests Details

### {ID} — {Test name}

**Severity:** {Critical | Mid | Low}
**Reason:** Below configured execution level ({EXECUTION_LEVEL})
```

#### 4.7 — Captured Screenshots

Always include — list all captured screenshots. Every `File` entry is a path relative to the test cases file's directory, always starting with `evidences/` since that is where every screenshot is saved (Step 3.2):

```markdown
## Captured Screenshots

| File                      | Description                              |
| ------------------------- | ----------------------------------------- |
| `evidences/filename.png`  | Description of what the screenshot shows |
```

#### 4.8 — Design Comparison (include only if a TC-DC test case was executed)

```markdown
## DESIGN COMPARISON

### Design Reference

- **Source**: {Figma frame URL or Pencil slide name}
- **Comparison date**: {report timestamp obtained as defined in Step 3.0, e.g. 2026-07-03 14:32:05}

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
- **Evidence**: {screenshot path relative to the test cases file's directory, e.g. `evidences/TC-DC-01-...png`}
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
- Use status emojis consistently: ✅ PASS, ❌ FAIL, ⚠️ BLOCKED, ⏭ SKIPPED.
- Keep section names in UPPERCASE where specified.
- Include aggregate metrics (totals, success rate — computed over executed test cases only, excluding skipped ones).
- Include the `EXECUTION_STARTED` / `EXECUTION_COMPLETED` report timestamps (Step 3.0) in the header and Executive Summary, and a filename timestamp on every captured screenshot (Step 3.2). Never omit them.
- Include every executed test case's own `TC_TIMESTAMP` and evidence file path directly in its section-table row (Timestamp / Evidence columns, Step 4.3) — never rely on the Captured Screenshots table (4.7) alone to establish that link.
- Include the `EXECUTION_LEVEL` used (Step 2a) in the Executive Summary, and never silently drop a skipped test case from its section table or from **Skipped Tests Details** (4.6).
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
- Total test cases executed, broken down by result (✅, ❌, ⚠️, ⏭).
- Success rate percentage (over executed test cases only).
- Execution level used (`EXECUTION_LEVEL`, Step 2a) and how many test cases were skipped because of it.
- Execution window (`EXECUTION_STARTED` – `EXECUTION_COMPLETED`, from Step 3.0).
- Number of screenshots captured.
- Key findings or issues discovered during execution (if any).
