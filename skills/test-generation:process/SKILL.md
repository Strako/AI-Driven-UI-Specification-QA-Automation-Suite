# Skill: test-generation:process

## Test Case Generation

You are acting as a QA engineer. Generate a complete set of test cases from the UI screen specification the user has provided or that was indicated via the `SPEC_FILE` input.

---

### Step 1 — Read required files

Before generating anything, read the following files in order:

1. The UI screen specification file indicated by `SPEC_FILE` (or the file the user referenced).
2. Every spec file listed under **Related Views → Spec File** in that specification. Read each one fully to understand its view ID, components, fields, validations, and flow.

> This skill never reads `BASE_URL` from `vars.md` and never resolves it into a concrete domain in `test-cases.md`. Test cases reference views and URLs symbolically (`<<view-id>>` / `{{BASE_URL}}`) so the same `test-cases.md` can run against any environment without regeneration — the actual `BASE_URL` value is looked up only at execution time, by the test-execution skill. The one exception is `test-data.md` generation under `AUTO_FILL_TEST_DATA` (Step 5), which does read `vars.md` — but only to resolve named credential variables into `test-data.md`, never `BASE_URL`, and never into `test-cases.md` itself.

---

### Step 2 — Apply the specification conventions

All output must follow the conventions defined in `TEMPLATE.md`. Apply them exactly.

**Field references**

- Reference every field, input, button, link, or interactive element using its `${field-name}` placeholder as defined in the spec.
- Never substitute `${field-name}` with a concrete value inside test cases.
- When a field belongs to a related view (not the current one), prefix it with its source view ID: `<<view-id>>.${field-name}`.

**View references**

- Reference every view using its `<<view-id>>` identifier as defined in the spec.

**Full URL construction**

- Never write a resolved domain or hostname into a test case — `BASE_URL` must always stay symbolic.
- When navigating to a view defined in the spec, reference it with its `<<view-id>>`. The test-execution skill resolves this to `{{BASE_URL}}` + that view's Route at run time.
- When a navigation target isn't backed by a spec'd view (an ad-hoc or external path), write it literally as `{{BASE_URL}}` + the path, e.g. `{{BASE_URL}}/reset-password?token=${token}`.
- Example: Route `/login` on `<<login-screen-f3a9c1b2>>` → reference it in the test case as `<<login-screen-f3a9c1b2>>`, never as `https://app.example.com/login`.

**Account-creation and credential fields**

- For a signup/registration test case, use the same generic `${field-name}` placeholders as any other field (e.g. `${email}`, `${password}`) and leave them blank in `test-data.md` — never invent or write a literal email address anywhere in `test-cases.md` or `test-data.md`.
- `test-execution` detects the signup test case automatically at run time, generates a fresh `qa-{random}@yopmail.com` identity for it, confirms it via Yopmail if the flow requires an OTP or confirmation link, and persists it to `vars.md` as `{{AUTH_EMAIL}}` / `{{AUTH_PASSWORD}}` (or whichever variable names `vars.md` uses) — reused by every other test case whose precondition requires a logged-in account. See `${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md` for the full procedure (also used by `spec-wizard-generate` when a spec's target page itself requires creating an account first).

---

### Step 3 — Determine coverage

Generate the optimal number of test cases for complete behavioral coverage. Do not use a fixed count per category — let the complexity of the spec determine it. Do not assume or invent behavior not explicitly described in the spec.

Cover every applicable test type:

- **Happy Path** — the main successful flow from entry to final state
- **Smoke** — minimum critical checks that confirm the view is functional
- **Functional** — detailed validation of each component, field rule, state transition, business rule, and action in the spec
- **Edge Case** — boundary conditions, empty states, max/min values, and unusual but valid interactions
- **Exploratory** — scenarios implied by the spec holistically that are not explicitly listed but follow logically from the described behavior
- **Design Comparison** — visual and structural comparison between the live page and the original design reference (only when `Pencil slide name / Figma frame URL` is provided in Screen Identification and is not empty, "N/A", or "Not provided")

Specifically ensure coverage of:

- Every field validation inside every component
- Every component-level validation
- Every validation defined on view-level fields
- Every named screen state and its transition conditions
- Every business rule — both the met path and the violated path
- Every action and its expected reaction
- Every cross-view scenario from the **Related Views** section — each cross-view test must be fully self-contained, starting with the setup steps in the related view and ending with the assertion in the current view
- For **External Service** entries: do not test the service directly; generate a test case that stubs or mocks it and asserts the expected behavior of the current view
- **Design Comparison** (when applicable): if the `Pencil slide name / Figma frame URL` field in Screen Identification contains a valid reference (not empty, not "N/A", not "Not provided"), generate exactly one Design Comparison test case following Rule 6 in TEMPLATE.md. This test case instructs the executor to retrieve the design from Figma MCP or Pencil MCP and compare it against the live page, documenting all visual and structural discrepancies.

Assign every test case a `Severity` of Critical, Mid, or Low following Rule 8 in TEMPLATE.md — judge it by business impact, not mechanically from `Type`. Design Comparison test cases are always Critical.

---

### Step 4 — Produce Artifact 1: test-cases.md

Write a file named `test-cases.md` in the same directory as the spec file, using the structure below. Each test case must reference fields and views using placeholders only — never concrete values.

```
# Test Cases — <<view-id>>

## [TC-001] (Title)

- **Type**: Happy Path | Smoke | Functional | Edge Case | Exploratory | Design Comparison
- **Severity**: Critical | Mid | Low (per Rule 8 in TEMPLATE.md — Design Comparison is always Critical)
- **Description**: (One sentence describing what this test validates)
- **Preconditions**: (Required state, session, data, or navigation before the test begins. Use <<view-id>> for views and ${field-name} for field values. For navigation, reference the destination as <<view-id>>, or as {{BASE_URL}} + path for ad-hoc paths not backed by a view — never write a resolved domain. Omit this block if there are no preconditions.)
- **Steps**:
  1. (Action — use ${field-name} for every interaction, <<view-id>> for every navigation)
  2. (...)
- **Expected Result**: (What the system must do or display)
```

Repeat the block for each test case.

---

### Step 5 — Produce Artifact 2: test-data.md

After writing `test-cases.md`, write a second file named `test-data.md` in the same directory. This is a standalone fillable document — it contains only data, never test logic.

Rules:

- Organize by scenario using the same TC IDs and titles from Artifact 1.
- Under each scenario, group fields by their source view using `<<view-id>>` as a section header.
- List every `${field-name}` referenced in the test case under the correct view section.
- Preserve the exact `${field-name}` identifiers from the spec — do not rename or alias them.
- Include only test cases that require input data; omit test cases with no field interactions.

**If `AUTO_FILL_TEST_DATA` is absent or not `true`** (the default): leave every field as an empty fill-in slot, exactly as below — a human will fill it in before execution.

```
# Test Data — <<view-id>>

## [TC-001] (Title)

### <<view-id>>
- ${field-name}:
- ${field-name}:

### <<related-view-id>>
- ${field-name}:
- ${field-name}:

## [TC-002] (Title)

### <<view-id>>
- ${field-name}:
```

**If `AUTO_FILL_TEST_DATA` is `true`**: fill every field with a concrete value instead of leaving it blank, using this order of precedence:

1. **Signup/registration credential fields** (per the "Account-creation and credential fields" rule in Step 2 above) — leave these blank regardless of `AUTO_FILL_TEST_DATA`. `test-execution` generates and confirms a fresh Yopmail identity for these at run time; writing a fabricated value here would only be overwritten or, worse, collide with that flow.
2. **Other credential-like fields tied to a named variable already resolvable from `vars.md`** (e.g. a login field whose precondition or component description references `{{AUTH_EMAIL}}`, `{{CLIENT_EMAIL}}`, or any other `{{VARIABLE_NAME}}` token from the spec's Business Rules): use `Read` on `vars.md` (path given by `PROJECT_ROOT`) and:
   - If the variable already holds a real (non-placeholder) value, write that literal value.
   - If it is still a placeholder, leave the field blank — fabricating a credential here would not match whatever account actually exists (or will be created) in the target application.
3. **Every other field** — infer a single plausible, realistic value from the field's name, type, and the spec's description/validation rules for it. Respect any stated format or constraint (e.g. a validated email field gets a well-formed email; a numeric field gets a number inside any stated range; a dropdown/select gets one of its documented options; a date field gets a plausible date in the format implied by the field). When nothing more specific is implied, prefer an unambiguous, obviously-a-test-value string (e.g. `Test Company Inc.`, `Test User`, `555-0100`) over something that could pass as real personal data.

Whether or not `AUTO_FILL_TEST_DATA` was set, the file's structure (headers, TC IDs, view sections, field list) is identical — only whether the value after `${field-name}:` is empty or filled in differs.

Repeat for each test case that requires input data.

---

### Step 6 — Report completion

Once both files are written, output the structured `---GENERATION-COMPLETE---` block as defined in the agent instructions, then provide a human-readable summary:

- Path to `test-cases.md` and total number of test cases generated, broken down by type and by severity (Critical/Mid/Low).
- Path to `test-data.md`, total number of scenarios included, and whether it was auto-filled (`AUTO_FILL_TEST_DATA`) or left blank for manual completion.
- Any related view spec files that were read and incorporated into cross-view test cases.
- Any assumptions made due to ambiguity in the spec (if any).
