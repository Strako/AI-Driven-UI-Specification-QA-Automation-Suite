# Skill: spec-wizard:improve

## Interactive Spec Improvement Wizard

You review and improve an **existing** UI screen specification file section by section. Walk through all 9 content sections in order. For each section, show the current content, ask targeted questions, apply the user's changes, and wait for explicit confirmation before advancing.

**This is a multi-turn interactive skill. Never advance to the next section without explicit user confirmation.**

Read before starting:

1. `TEMPLATE.md` at the project root — canonical spec format and section structure
2. `vars.md` — for BASE_URL
3. `SPEC_FILE` (provided in your input) — the existing spec to improve

---

## Startup

Parse the spec file and extract the current content of each section into memory. Keep a live in-memory draft that you update as the user confirms each section. Do NOT write the file until the user approves the Final Review.

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✏️   SPEC IMPROVEMENT WIZARD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Spec file  : {SPEC_FILE}
Module     : {module-name}
Sections   : 9 to review

At each section you can:
  next / yes  — keep as-is and continue
  skip        — keep as-is and continue (no questions)
  <describe>  — describe changes and I'll apply them

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Section Protocol (apply to every section)

Use this exact layout for every section:

```
─────────────────────────────────────────────────────────────
SECTION {N}/9 — {Section Name}
─────────────────────────────────────────────────────────────
CURRENT CONTENT:

{current section content from spec, formatted exactly as in TEMPLATE.md}

─────────────────────────────────────────────────────────────
{section-specific questions}

→  next / yes  to keep and continue  |  describe changes  |  skip
```

**WAIT for the user's response before doing anything else.**

If the user describes changes:

1. Apply to the in-memory draft
2. Show the updated section content
3. Ask: "Updated. Anything else, or type **next** to continue?"
4. Wait again.

If the user types `next`, `yes`, or `skip`: lock the section in the draft and proceed to the next section.

---

## Section 1 — Screen Identification

Show current Screen Identification block.

Section-specific questions:

> - Is the View ID correct? _(it's permanent once locked — only change if it was wrong)_
> - Is the Name, Version, and Route correct?
> - Is the **Pencil slide name / Figma frame URL** correct? If you have a Figma frame URL or a Pencil slide name for this view's design, provide it here. This enables design-vs-implementation comparison during test execution.
>   - Figma example: `https://www.figma.com/design/abc123/MyProject?node-id=1234-5678`
>   - Pencil example: `Login Screen` (the slide name in a .pen file)

---

## Section 2 — Origin Context

Show current Origin Context block.

Section-specific questions:

> - What view does the user come **from** to reach this page? (or is it a direct entry point?)
> - Is the start flow description accurate?

---

## Section 3 — Components

This section is reviewed **one component at a time**.

For each component, show its full block, then ask:

> **Component "{name}":**
>
> 1. Is the component name and role correct?
> 2. Is there a **component-level validation** that applies to the whole component?
>    (e.g. "on failed submit, a toast appears saying 'Invalid credentials'")
>    → rule, error message, condition that triggers it
> 3. For each field — is the type, placeholder, and required status correct?
> 4. For each field — what **validation rule and error message** apply?
>    (omit for buttons and links)
> 5. Are any fields **missing**? Describe each: name, type, required, placeholder.
> 6. Should any fields be **renamed**?

After all existing components are confirmed:

> Are there **additional components** to add? (e.g. a sidebar, modal, notification panel)
> Describe each one. Type **next** when done adding.

For each new component described by the user:

- Generate Component ID: `<<{kebab-name}-{8-char-hex}>>`
- Generate field names: `${module-fieldpurpose}` (module-prefixed, kebab-cased)
- Show the full component block in TEMPLATE.md format
- Ask the same 6 questions above

---

## Section 4 — View-Level Fields

Show current View-Level Fields block.

Section-specific questions:

> - Are there interactive elements that exist **directly in the view** but don't belong to any component?
>   (e.g. a global error banner, floating action button, top-level navigation link)
> - If yes: name, type, required, any validation and error message.
> - If none: type **next**.

---

## Section 5 — Screen States

Show current Screen States block.

Section-specific questions:

> - Is each state correctly identified? Common states: `idle`, `loading`, `error`, `success`, `empty`, `disabled`
> - For each state: is the **transition target** correct? The **trigger** correct? The **change conditions** correct?
> - Are there states I missed?

---

## Section 6 — Related Views

Show current Related Views block.

Section-specific questions:

> - **Spec Files** — are there other views that must be set up first to fully test this one?
>   If yes: spec file path, relationship, test context.
> - **External Services** — does this view interact with any external services?
>   (Google OAuth, Stripe, SendGrid, Google Maps, etc.)
>   If yes: service name, role in this view, test notes.
> - If neither: type **next**.

---

## Section 7 — Business Rules

Show current Business Rules block.

Section-specific questions:

> - Are the listed rules correct? Remove or correct any that are wrong.
> - For each rule: is the **condition** correct? The **action** (success path + violation path)?
> - Additional rules to consider:
>   - Who can access this view? (role / permission gate)
>   - Are there data limits? (max items, numeric ranges)
>   - Status gates? (only published items appear)
>   - Ownership rules? (user can only edit their own content)
>   - Time / date constraints?
> - If no rules apply beyond field validations: type **next**.

---

## Section 8 — Actions and Transitions

Show current Actions and Transitions block.

Section-specific questions:

> - For each action: is the **transition target** correct? The **expected reaction** correct?
>   (Include: validation fires first? loading state? navigation on success?)
> - Actions I may have missed:
>   - Keyboard shortcuts
>   - Row clicks in tables
>   - Inline edit actions
>   - Pagination / filter controls
>   - Drag / drop interactions

---

## Section 9 — Detailed Flow Description

Show current Detailed Flow Description.

Section-specific questions:

> - Is this narrative correct and complete?
> - Should any steps be added, modified, or removed?
> - Are there edge cases or alternative flows worth capturing?

After the user confirms or edits section 9, **do NOT show a "next" prompt** — proceed automatically to the Final Review.

---

## Final Review and Save

Print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅  ALL 9 SECTIONS REVIEWED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Show the **complete updated spec** as a preview (full file content in a code block).

Ask:

> **Ready to save?**
> Type **save** (or **yes**) to write the file, or describe any final edits.

Once confirmed:

1. `Write` the full updated spec to `SPEC_FILE` (overwrite the existing file)

Print:

```
✅  Spec updated: {SPEC_FILE}
```

---

## Next Step — Always Required After Saving

After the updated spec is written, you MUST immediately invoke the pipeline offer. Do not stop here.

Use the **Skill** tool now:

- skill: `spec-wizard:pipeline-offer`
- args: `SPEC_FILE={SPEC_FILE} PROJECT_ROOT={project-root}`

> This step is mandatory. Never end the conversation after the wizard without invoking the pipeline offer.
