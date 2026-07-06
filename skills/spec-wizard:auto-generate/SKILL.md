# Skill: spec-wizard:auto-generate

## Automatic UI Specification Generator

You generate a **complete** UI screen specification in one pass using Playwright MCP — no section-by-section questions. Produce the best possible spec from what you can see and infer, then write the file.

Read before starting:

1. `TEMPLATE.md` at the project root — canonical output format
2. `vars.md` at the project root — extract `BASE_URL` and any authentication credential variables (e.g. `AUTH_EMAIL`, `AUTH_PASSWORD`, or custom variable names specified by the user)
3. `${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md` — the shared procedure Phase 1.1 delegates to whenever the page under analysis requires creating a new account first (see Phase 1.1 below)

---

## Phase 0 — Collect Inputs

If `CALLER` is present in your input (this run was dispatched by another agent, e.g. `qa-coordinator`, not typed directly by a human at this prompt), **never print the interactive question block below**. Use only the inputs already given, and fill anything still missing with a sensible default instead of stopping to ask:

- `AUTH_REQUIRED` missing → `none`
- `OUTPUT_DIR` missing → `Platform/{ModuleName}/`
- `DESIGN_REFERENCE` missing → `Not provided`
- `MODULE_NAME` missing → derive from the last segment of `PAGE_URL`

Print the `✅ Starting analysis…` confirmation block below either way, then proceed immediately.

If `CALLER` is absent (a human is driving this conversation directly) and required values are not already present in your input, ask for all of them in a **single message**:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍  SPEC AUTO-GENERATOR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
To generate the spec I need:

1. Page URL (required) — full URL or path (paths resolved as BASE_URL + path)
2. Module name (optional) — kebab-case, e.g. "login", "job-detail"
   Derived from last URL segment if omitted.
3. Authentication — does this page require an authenticated session? (none / existing account / new account)
   - **none** — skip authentication entirely.
   - **existing account** — an account already exists. Provide the login route and credential variable names from vars.md:
     - email/user variable name (e.g. AUTH_EMAIL, USER_VAR)
     - password variable name (e.g. AUTH_PASSWORD, PASSWORD_VAR)
     - destination route after login
   - **new account** — no account exists yet; one must be created before this page can be analyzed. Provide the signup/registration route and credential variable names from vars.md:
     - email variable name (e.g. AUTH_EMAIL) — if this variable in vars.md is still a placeholder or blank, a fresh `@yopmail.com` identity is generated automatically and persisted to vars.md for future runs; if it already holds a real value, that existing identity is reused instead of creating a new one
     - password variable name (optional — omit for passwordless/magic-link signups)
     - destination route after account creation completes
     Any OTP, confirmation code, or confirmation link required to finish creating the account is retrieved automatically from Yopmail in a second browser tab — never ask the user for it.
   In every case, the actual credential values are read from (and, for "new account", written to) vars.md at runtime — never hardcode credentials.
4. Output directory — where to save the spec (default: Platform/{ModuleName}/)
5. Design reference (optional) — Pencil slide name or Figma frame URL
   Used for design-vs-implementation comparison during test execution.
   Examples:
   - Figma: https://www.figma.com/design/abc123/MyProject?node-id=1234-5678
   - Pencil: "Login Screen" (name of the slide in a .pen file)
```

Once all inputs are confirmed, print the confirmation block and proceed immediately — do not wait for further approval:

```
✅  Starting analysis…

  Target URL       : {full URL}
  Module           : {module-name}
  Auth             : none / existing account / new account
  Auth credentials : email={VAR_NAME} password={VAR_NAME or "none"} (from vars.md)
  Design reference : {Figma URL or Pencil slide name or "Not provided"}
  Output file      : {output-dir}/{module-name}-description.md
```

---

## Phase 1 — Navigate and Analyze

> ⛔ **CRITICAL — Playwright MCP only. Never write code.**
> All browser interactions MUST be performed exclusively through **Playwright MCP tool calls** using the prefix `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__`.
> NEVER write or run Node.js/JavaScript Playwright code (`require('playwright')`, `@playwright/test`, `page.goto()`, `page.screenshot()`, `chromium.launch()`, `npx playwright`, etc.).
> NEVER use `Bash` to run any Playwright scripts or CLI commands for browser automation.
> The tools below are MCP tool invocations — call them directly as tools, not as code.

Tool prefix for every browser call: **`mcp__plugin_AI-Driven-UI-Specification_playwright_headed__`**

### 1.1 — Authenticate (if required)

Branch on the Auth answer from Phase 0.

#### 1.1a — Existing account (login)

1. Read `vars.md` and extract the credential values using the variable names provided by the user (e.g. if user said `email: AUTH_EMAIL, password: AUTH_PASSWORD`, look for `AUTH_EMAIL = ...` and `AUTH_PASSWORD = ...` in vars.md).
2. `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_navigate` to the login URL
3. `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_snapshot` — identify email/username field, password field, submit button by `ref=`
4. `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_type` email/username (using the value from vars.md) → `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_type` password (using the value from vars.md) → `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_click` submit
5. `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_snapshot` — verify navigation away from login
6. If still on login page: continue and note "Auth status: unconfirmed" in spec

#### 1.1b — New account (create via Yopmail)

Follow `${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md` completely, applied as:

1. **Step A** — read the specified credential variable(s) from `vars.md` and detect placeholder/blank vs. real values.
2. **If a real identity is already persisted** — an account was already created by a previous run. Do not sign up again:
   - If a separate `LOGIN_ROUTE` was also given for this page, repeat **1.1a** with the persisted credentials.
   - Otherwise, treat the persisted identity as already authenticated for this session's purposes and continue directly to Phase 1.2.
3. **If the credential(s) are still unset** — generate a fresh identity (**Step B**): email = `qa-{random}@yopmail.com`, plus a password (`Qa!{random}9`) only if a password variable was specified.
4. Navigate to `SIGNUP_ROUTE`, snapshot to identify the form fields by `ref=`, type the generated value(s) into the matching fields, and submit (**Step C**).
5. If the app requires an OTP, confirmation code, or confirmation link before the account is usable, complete **Step D** — opens `https://yopmail.com/en/` in a second tab, retrieves the code or clicks the confirmation link, then switches back to the original tab and continues the form flow.
6. **Only if account creation is confirmed successful** (navigation away from the signup form to an authenticated state, or a success message/state, or — when Step D applied — confirmation completing without error): persist the generated value(s) to `vars.md` (**Step E**).
7. If account creation did not succeed, leave the placeholders untouched, note "Auth status: account creation failed" in the spec, and continue to Phase 1.2 anyway using whatever page state resulted — do not abandon the whole spec generation over this.
8. Once authenticated (or after step 7's note), navigate to `DESTINATION_ROUTE` if one was given, then continue to Phase 1.2.

### 1.2 — Navigate to target page

`mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_navigate` to the full target URL if not already there.

### 1.3 — Capture the page

1. `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_take_screenshot` — save as `{module-name}-analysis.png` in output dir
2. `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_snapshot` — full accessibility tree
3. Scroll to bottom: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate` with `window.scrollTo(0, document.body.scrollHeight)`, then `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_snapshot` again
4. Interact with visible tabs, accordions, or expandable sections to capture hidden content; take snapshots after each

### 1.4 — Build internal analysis

From all snapshots, identify and record:

**Components** (forms, cards, panels, navbars, tables, sidebars, modals, footers):

- Descriptive name
- Role (what it does on this page)
- Each field: purpose, type (input/password/email/number/dropdown/radio/checkbox/button/link/textarea/file/other), placeholder text, required indicator (asterisk / aria-required / "required" label), visible validation messages

**View-level fields** (outside every component):

- Global error banners, floating action buttons, top-level navigation links

**Visible states** (loading spinners, empty state messages, success/error toasts, disabled elements)

**User actions** (every button, link, and form submit — purpose + likely destination)

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅  Analysis complete
   URL        : {url}
   Components : {N} — {list names}
   Fields     : {N total}
   Actions    : {N}
   States     : {N}
Generating spec…
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase AUTO — Generate Complete Spec

Using all data from Phase 1, generate every section of the spec. Fill in the best possible value for each. Where behavior cannot be confirmed from the DOM, make the most reasonable inference and add a note `— verify in wizard`.

### Screen Identification

- **View ID**: `<<{module-name}-{8-char-lowercase-hex}>>` — generate fresh random hex
- **Name**: detected page title or main heading
- **Version**: `0.1.0`
- **Route**: path only (no domain, no protocol)
- **Pencil slide name / Figma frame URL**: use the `DESIGN_REFERENCE` value provided by the user. If not provided, write `Not provided`

### Origin Context

- Infer from URL structure: e.g. `/jobs/123/detail` → previous view likely `/jobs`
- If the page is an entry point: `Direct entry — no prior view required`
- If genuinely unknown: `Not determined — refine using the improvement wizard`

### Components

For each detected component:

- **Component ID**: `<<{kebab-name}-{8-char-lowercase-hex}>>` — generate fresh
- For each field:
  - Include **Validation** block only when a validation message was visible or a required indicator was detected
  - Unknown validations: mark `Rule: Not detected — refine using the improvement wizard`
  - Unknown required status: default to `no`

### View-Level Fields

- List any fields detected outside all components
- If none: `Not applicable to this definition`

### Screen States

- Always include `idle` (default state on load)
- Add `loading`, `error`, `success`, `empty` only if detected in the DOM
- Transition targets: infer from button/link destinations when possible; unknown targets → `Not determined`

### Related Views

- Suggest routes found in navigation links as candidates (note: "detected in DOM — confirm relationship")
- External services: infer from OAuth/SSO buttons, payment widgets, map embeds, etc.
- If nothing detected: `Not applicable to this definition`

### Business Rules

- If auth was required: generate `<<rule-auth-required-{hex}>>` with description "Page requires authenticated session"
- Role/permission gate if detected (admin-only badge, role guard in DOM): generate rule
- Any other clearly inferable business rule: generate with hex UUID
- Nothing inferable beyond field validations: `Not applicable to this definition`

### Actions and Transitions

- Every detected button, link, and form submit gets an entry
- `${field-name}` derived from the element's label/purpose, kebab-cased, module-prefixed
- Transition: infer from href or button purpose; unknown → `Not determined`
- Expected Reaction: infer from label and context

### Detailed Flow Description

Generate a step-by-step narrative that connects all sections:

- Use `${field-name}` for every user interaction
- Use `<<view-id>>` for every navigation reference
- Include auth flow if applicable
- Note inferred vs. confirmed behavior explicitly

### LLM Instructions — Test Case Generation

Copy the full **LLM Instructions — Test Case Generation** section verbatim from `TEMPLATE.md`. Do not alter a single word.

---

## Phase REQUIREMENTS — Enrich Spec with Project Requirements

Before saving the spec to disk, offer the user an opportunity to enrich the generated spec with project requirements or user stories. This step refines the **in-memory spec draft** before writing.

**If `REQUIREMENTS_NOTE` is present in your input** (supplied by a caller such as qa-coordinator, not typed by a human at this prompt): skip the interactive prompt below entirely. Treat every sentence in `REQUIREMENTS_NOTE` as a requirement relevant to this view and apply it directly to the in-memory draft using the same rules as the "user provides a file path" case further down (Components/Fields, Business Rules, Screen States, Actions and Transitions, Detailed Flow Description) — including the **Multi-role / embedded credential variables** handling below wherever the note names more than one credential variable. Print the `✅ Requirements enrichment applied` summary (source: `REQUIREMENTS_NOTE`), then proceed to **Write the Spec File**.

Otherwise, print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋  REQUIREMENTS ENRICHMENT (optional)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The spec has been generated from the live page.
Before saving, would you like to enrich it with project requirements?

  • Provide a file path  —  path to an .xlsx, .csv, or .md file containing
    user stories or requirements for the platform
    (e.g. /path/to/requirements.md)

  • Type  docs  —  auto-scan the docs/ folder at the project root

  • Type  skip  —  save the spec as-is without requirements enrichment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Wait for the user's response before proceeding.**

### If the user provides a file path:

1. Determine the file extension:
   - **.md or .csv**: Use `Read` to load the file contents. If the file exceeds 500 lines, read the first 500 lines as a representative sample and note the truncation.
   - **.xlsx**: Binary Excel files cannot be read directly. Inform the user and ask them to re-export as `.csv` or `.md` and provide the new path, or type `skip` to continue without enrichment.
2. From the file contents, identify every requirement, user story, or acceptance criterion **relevant to this specific view** — matched by any of: module name, route path, detected component names, or related feature keywords inferred from the DOM analysis.
3. Discard requirements clearly aimed at unrelated modules or unrelated functionality.
4. Apply the relevant requirements to the **in-memory spec draft** — do not write the file yet:
   - **Components / Fields**: Add or correct fields described in requirements (e.g., "The dashboard must show total active jobs" → ensure a stats component contains this field).
   - **Business Rules**: Add rules derived from acceptance criteria (e.g., "Only admin users may access this page" → add a business rule with a generated `<<rule-uuid>>`).
   - **Screen States**: Add named states explicitly mentioned in requirements.
   - **Actions and Transitions**: Add or correct transitions described in user stories.
   - **Detailed Flow Description**: Expand the narrative with requirement-driven scenarios.
5. Print a summary before proceeding to Write:

```
✅  Requirements enrichment applied

  Source          : {file path}
  Relevant items  : {N} requirements matched to {module-name}
  Changes applied :
    • {list each addition or correction, one per bullet}
```

### If the user types `docs`:

1. Use `Bash` to list the contents of `docs/` at the project root:
   `ls "{project-root}/docs/" 2>/dev/null || echo "(empty)"`
2. If the folder is empty or does not exist:
   Print: `⚠️  No files found in docs/. Saving spec as generated.`
   Proceed immediately to Write phase.
3. If files are found:
   - Use `Read` to load every `.md` and `.csv` file found in `docs/`. Skip `.xlsx` and other binary files and note them as unreadable.
   - Apply the same relevance filtering and in-memory spec refinement described in the file-path case above.
4. Print a summary:

```
✅  Requirements enrichment applied from docs/

  Files scanned   : {list of files read}
  Relevant items  : {N} requirements matched to {module-name}
  Changes applied :
    • {list each addition or correction}
```

### Multi-role / embedded credential variables

This applies whenever the page's *content* — not the page-gating Auth question in Phase 0, but a component inside the page such as an embedded login form usable by more than one role — needs more than one named credential variable pair (e.g. a role-selectable login usable by `CLIENT_EMAIL`/`CLIENT_PASSWORD` for one role and `PROVIDER_EMAIL`/`PROVIDER_PASSWORD` for another). This can come from `REQUIREMENTS_NOTE`, a requirements file, `docs/`, or direct DOM analysis of the component itself. Whenever it applies:

1. Pair every email variable with the password variable the source explicitly assigns to the *same* role — never by position, order of appearance, or guesswork. If a pairing is ambiguous or contradicted mid-message (e.g. the source corrects itself), use the final, explicitly corrected pairing.
2. Add (or extend) a Business Rule in the spec — `<<multi-role-login-{hex}>>` — describing the roles, which variable pair authenticates which role, and any stated constraint (e.g. "plain email/password only, no social login"). Reference each credential using `{{VARIABLE_NAME}}` tokens per TEMPLATE.md's Environment Variable Placeholder Format — never a literal value.
3. Reference the same `{{VARIABLE_NAME}}` tokens in the login component's field/precondition descriptions where relevant, exactly like `{{AUTH_EMAIL}}` / `{{AUTH_PASSWORD}}` are used elsewhere in this suite.
4. Read `vars.md`. For every variable name used this way that does **not** already have a line in `vars.md`, use `Edit` to append a new placeholder line before saving the spec, following the existing seed-variable format, e.g.:
   ```
   CLIENT_EMAIL = your-login-email@example.com
   CLIENT_PASSWORD = your-login-password
   ```
   Never invent or write a real credential value here — only placeholder text, exactly like the seed `AUTH_EMAIL` / `AUTH_PASSWORD` lines.
5. Mention every newly added placeholder variable in the enrichment/save summary so the user knows to fill them in with real test credentials before test execution.

### If the user types `skip` (or any variant: "no", "none", "not now"):

Print:
```
Skipping requirements enrichment. Saving spec as generated.
```
Proceed immediately to Write phase.

---

## Write the Spec File

1. `Bash`: `mkdir -p {output-dir}`
2. `Write`: save the complete spec to `{output-dir}/{module-name}-description.md`

Print:

```
✅  Spec saved: {output-dir}/{module-name}-description.md
```

---

## Next Steps — Always Required After Saving

After the spec file is written:

**If `CALLER` is present in your input**, skip Steps 1–2 below entirely — do not ask about the wizard, and do not dispatch `spec-wizard-improve` or `spec-wizard-pipeline`. Instead output:

```
---SPEC-GENERATED---
SPEC_FILE: {absolute-path-to-spec}
MODULE: {module-name}
---SPEC-GENERATED-END---
```

followed by a brief one-line human-readable summary, and stop — control returns to `CALLER`.

**Otherwise** (a human is driving this conversation directly), you MUST always complete the following steps. Do not stop after saving.

### Step 1 — Ask about the improvement wizard

Ask the user this exact question:

> The spec for **{module-name}** has been generated.
> Would you like to run the improvement wizard to review and refine each section interactively?
>
> - **yes** → opens the spec improvement wizard
> - **no** → goes straight to the QA pipeline offer

### Step 2 — Route based on user response

**If the user says yes (or ok / sure / yep / proceed):**

Use the **Agent** tool immediately to dispatch the improvement wizard agent:

```
Dispatch subagent: spec-wizard-improve

SPEC_FILE: {absolute-path-to-spec}
PROJECT_ROOT: {project-root}

Run the interactive spec improvement wizard on the spec file above.
```

**If the user says no (or nope / skip / later / not now):**

Use the **Agent** tool immediately to dispatch the pipeline-offer agent:

```
Dispatch subagent: spec-wizard-pipeline

SPEC_FILE: {absolute-path-to-spec}
PROJECT_ROOT: {project-root}

Show the spec summary and offer the QA pipeline for the spec above.
```

> These two steps are mandatory. Never end the conversation after saving the spec file without completing them. Do not try to invoke `spec-wizard:improve` or `spec-wizard:pipeline-offer` via the Skill tool — this agent's `tools:` frontmatter does not grant Skill or Agent(qa-coordinator) access, so that path is a dead end. Always go through the dedicated agent via the Agent tool instead.
