# Skill: spec-wizard:auto-generate

## Automatic UI Specification Generator

You generate a **complete** UI screen specification in one pass using Playwright MCP — no section-by-section questions. Produce the best possible spec from what you can see and infer, then write the file.

Read before starting:

1. `TEMPLATE.md` at the project root — canonical output format
2. `vars.md` at the project root — extract `BASE_URL` and any authentication credential variables (e.g. `AUTH_EMAIL`, `AUTH_PASSWORD`, or custom variable names specified by the user)

---

## Phase 0 — Collect Inputs

If these values are not already present in your input, ask for all of them in a **single message**:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍  SPEC AUTO-GENERATOR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
To generate the spec I need:

1. Page URL (required) — full URL or path (paths resolved as BASE_URL + path)
2. Module name (optional) — kebab-case, e.g. "login", "job-detail"
   Derived from last URL segment if omitted.
3. Authentication — does this page require login? (yes / no)
   If yes → login route and credential variable names from vars.md:
     - email/user variable name (e.g. AUTH_EMAIL, USER_VAR)
     - password variable name (e.g. AUTH_PASSWORD, PASSWORD_VAR)
     - destination route after login
   The actual values are read from vars.md at runtime — never hardcode credentials.
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
  Auth             : yes / no
  Auth credentials : email={VAR_NAME} password={VAR_NAME} (from vars.md)
  Design reference : {Figma URL or Pencil slide name or "Not provided"}
  Output file      : {output-dir}/{module-name}-description.md
```

---

## Phase 1 — Navigate and Analyze

> ⛔ **CRITICAL — Playwright MCP only. Never write code.**
> All browser interactions MUST be performed exclusively through **Playwright MCP tool calls** using the prefix `mcp__playwright_headed__`.
> NEVER write or run Node.js/JavaScript Playwright code (`require('playwright')`, `@playwright/test`, `page.goto()`, `page.screenshot()`, `chromium.launch()`, `npx playwright`, etc.).
> NEVER use `Bash` to run any Playwright scripts or CLI commands for browser automation.
> The tools below are MCP tool invocations — call them directly as tools, not as code.

Tool prefix for every browser call: **`mcp__playwright_headed__`**

### 1.1 — Authenticate (if required)

1. Read `vars.md` and extract the credential values using the variable names provided by the user (e.g. if user said `email: AUTH_EMAIL, password: AUTH_PASSWORD`, look for `AUTH_EMAIL = ...` and `AUTH_PASSWORD = ...` in vars.md).
2. `mcp__playwright_headed__browser_navigate` to the login URL
3. `mcp__playwright_headed__browser_snapshot` — identify email/username field, password field, submit button by `ref=`
4. `mcp__playwright_headed__browser_type` email/username (using the value from vars.md) → `mcp__playwright_headed__browser_type` password (using the value from vars.md) → `mcp__playwright_headed__browser_click` submit
5. `mcp__playwright_headed__browser_snapshot` — verify navigation away from login
6. If still on login page: continue and note "Auth status: unconfirmed" in spec

### 1.2 — Navigate to target page

`mcp__playwright_headed__browser_navigate` to the full target URL if not already there.

### 1.3 — Capture the page

1. `mcp__playwright_headed__browser_take_screenshot` — save as `{module-name}-analysis.png` in output dir
2. `mcp__playwright_headed__browser_snapshot` — full accessibility tree
3. Scroll to bottom: `mcp__playwright_headed__browser_evaluate` with `window.scrollTo(0, document.body.scrollHeight)`, then `mcp__playwright_headed__browser_snapshot` again
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

## Write the Spec File

1. `Bash`: `mkdir -p {output-dir}`
2. `Write`: save the complete spec to `{output-dir}/{module-name}-description.md`

Print:

```
✅  Spec saved: {output-dir}/{module-name}-description.md
```

---

## Next Steps — Always Required After Saving

After the spec file is written, you MUST always complete the following steps. Do not stop after saving.

### Step 1 — Ask about the improvement wizard

Ask the user this exact question:

> The spec for **{module-name}** has been generated.
> Would you like to run the improvement wizard to review and refine each section interactively?
>
> - **yes** → opens the spec improvement wizard
> - **no** → goes straight to the QA pipeline offer

### Step 2 — Route based on user response

**If the user says yes (or ok / sure / yep / proceed):**

Use the **Skill** tool immediately to invoke the improvement wizard:

- skill: `spec-wizard:improve`
- args: `SPEC_FILE={absolute-path-to-spec} PROJECT_ROOT={project-root}`

**If the user says no (or nope / skip / later / not now):**

Use the **Skill** tool immediately to invoke the pipeline offer:

- skill: `spec-wizard:pipeline-offer`
- args: `SPEC_FILE={absolute-path-to-spec} PROJECT_ROOT={project-root}`

> These two steps are mandatory. Never end the conversation after saving the spec file without completing them.
