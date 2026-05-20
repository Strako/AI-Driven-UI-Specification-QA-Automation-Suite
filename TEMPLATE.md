# UI Screen Specification Standard

---

## Syntax Convention

### ID Format

All entities — views and components — are identified using the following format:

```
<<readable-name-uuid>>
```

- `readable-name` — Human-assigned, descriptive, kebab-case label
  - Examples: `login-screen`, `auth-form`, `email-input`
- `uuid` — System-generated short UUID, ensures uniqueness across branches and teams
  - Example: `f3a9c1b2`

**Entity ID examples:**

- View: `<<login-screen-f3a9c1b2>>`
- Component: `<<auth-form-c4d7e2a1>>`

---

### Dynamic Placeholder Format

All user-interactable elements — text inputs, dropdowns, radio buttons, checkboxes, selectors, buttons, and links — are referenced using the following unified syntax:

```
${field-name}
```

**Usage examples:**

- Text input: `${email}`
- Password input: `${password}`
- Dropdown selection: `${country}`
- Radio button: `${payment-method}`
- Button / action trigger: `${submit}`
- Link / navigation action: `${forgot-password}`

> `${field-name}` represents both **what the field is** and **what the user provided or triggered**. All user interactions collapse into this single unified reference regardless of the underlying UI element type.

---

## Screen Description Template

> **One spec file = one view.** Each file defines exactly one `<<view-id>>`. Components and view-level fields are contained within that single view.

---

### Screen Identification

- **View ID**: `<<view-name-uuid>>`
- **Name**: (Descriptive name of the view)
- **Version**: (Design or template version)
- **Route**: (The path for this view relative to the base — e.g. `/login`, `/jobs/public`)
  > The full URL is resolved by combining `BASE_URL` from `vars.md` (project root) with this route.
  > Never define the domain or protocol here — only the path.
  > Example: `BASE_URL=https://app.example.com` + `/login` → `https://app.example.com/login`

---

### Origin Context

- **Previous View**: `<<previous-view-name-uuid>>` _(if applicable — the view the user navigated from)_
- **Start Flow**: (Brief description of the flow that leads to this view)

---

### Components

> Components are the named UI sections of this view (forms, panels, tables, modals, etc.).
> Each field, button, and interactive element must belong to a component whenever possible.
> Fields that cannot be reasonably grouped into a component are defined in **View-Level Fields** below.

Repeat the full block for each component.

---

- **Component**: `<<component-name-uuid>>`
  - **Name**: (Human-readable name of the component)
  - **Role**: (What this component does in the context of this view)
  - **Component Validation**: _(optional — a validation that applies to the component as a whole, not to a single field)_
    - **Rule**: (Description of the component-level rule)
    - **Message**: (Error or feedback message shown if the rule is not met)
    - **Condition**: _(optional — in what state or context this rule applies)_
  - **Fields**:
    - **Field**: `${field-name}`
      - **Type**: (text | password | email | number | dropdown | radio | checkbox | button | link | file | textarea | other)
      - **Placeholder**: tu@gmail.com
      - **Required**: (yes | no)
      - **Validation**: _(omit block if no validation applies)_
        - **Rule**: (Description of the validation rule for this field)
        - **Message**: (Error message shown if the rule is not met)
        - **Condition**: _(optional — if this validation only applies in a specific state or external flow)_
    - **Field**: `${field-name}`
      - **Type**: (...)
      - **Placeholder**: tu@gmail.com
      - **Required**: (yes | no)
      - **Validation**:
        - **Rule**: (...)
        - **Message**: (...)
        - **Condition**: _(optional — if this validation only applies in a specific state or external flow)_

---

_(repeat Component block for each component)_

---

### View-Level Fields

> Use this section only for interactive elements that exist directly in the view and do not belong to any component — for example, a global error banner, a page-level action button, or a floating navigation element.
> If all fields are covered by components above, this section can be omitted.

- **Field**: `${field-name}`
  - **Type**: (text | button | link | other)
  - **Required**: (yes | no)
  - **Validation**: _(omit if no validation applies)_
    - **Rule**: (...)
    - **Message**: (...)
    - **Condition**: _(optional)_

---

_(repeat View-Level Field block as needed)_

---

### Screen States

> Named states the view can be in. Repeat the block for each state.

- **State**: (state name — e.g. `idle`, `loading`, `error`, `success`, `empty`)
  - **Transition to**: `<<view-name-uuid>>` or (state name)
  - **Triggered by**: `${field-name}`
  - **Change Conditions**: (What must happen for the view to enter this state)

---

### Related Views

> Views or external services whose flows are required to generate a complete set of test cases for this view.
>
> Use **Spec File** entries for other views that have their own specification file — the LLM will read those files to understand fields, validations, and flows when generating cross-view test cases.
>
> Use **External Service** entries for third-party systems with no local spec file — these are considered for test awareness only and should be mocked or stubbed in tests.
>
> Repeat the appropriate block for each related view or service.

---

**Spec File:**

- **Related View**: `<<view-name-uuid>>` → `./relative/path/to/spec.md`
  - **Relationship**: (Explain why this view is needed to fully test the current view — e.g. "admin must create a job through this view before the public listing can be asserted")
  - **Test Context**: (Describe the scenario steps that happen in this external view as part of a cross-view test — e.g. "log in as admin, create a published job, return to this view and assert the job appears in the listing")

---

**External Service:**

- **External Service**: (Service name — e.g. Google OAuth, Stripe, SendGrid)
  - **Description**: (What role this service plays in the flow of this view)
  - **Test Note**: Not directly tested. Mock or stub this service in tests. Consider its behavior when defining expected outcomes.

---

### Business Rules

> Rules that govern the behavior of this view beyond individual field validations. Repeat the block for each rule.

- **Rule**: `<<rule-name-uuid>>`
  - **Description**: (Clear description of the business rule)
  - **Condition**: (In what context or state this rule applies)
  - **Action**: (What happens when the rule is triggered — success path and/or violation path)

---

### Actions and Transitions

> Every user-triggered action that causes a state change or navigation. Repeat the block for each action.

- **User Action**: `${field-name}`
  - **Transition**: `<<view-name-uuid>>` or (state name)
  - **Expected Reaction**: (What should happen immediately after this action — validations fired, state entered, navigation triggered, etc.)

---

### Detailed Flow Description

(Step-by-step narrative of how a user moves through this view from entry to exit. Reference `<<view-ids>>` for every navigation point and `${field-name}` for every user interaction. Include real-time validation behavior, state transitions, and any cross-view scenarios defined in Related Views that are required to set up or assert the state of this view.)

---

## LLM Instructions — Test Case Generation

> **Read this section carefully before generating any test cases.**

When generating test cases from a filled instance of this template, strictly follow all rules below.

---

### Rule 1 — Test Cases Must Be Data-Agnostic

Never hardcode concrete values inside test cases. Reference all input values using the `${field-name}` placeholder convention defined in this specification. When a field comes from a related view, reference it in the form `<<view-id>>.${field-name}` to make its origin explicit.

**Correct:**

```
GIVEN the user enters <<login-screen-f3a9c1b2>>.${email} and <<login-screen-f3a9c1b2>>.${password}
WHEN they trigger <<login-screen-f3a9c1b2>>.${submit}
THEN the system transitions to <<dashboard-a1b2c3d4>>
```

**Incorrect:**

```
GIVEN the user enters "admin@example.com" and "secret123"
WHEN they click Login
THEN the system goes to the dashboard
```

---

### Rule 2 — Cover All Specified Scenarios

Generate test cases that cover:

- Every field validation inside every component block
- Every component-level validation
- Every validation defined for view-level fields
- Every named state in Screen States
- Every business rule in Business Rules
- Every action in Actions and Transitions
- The happy path
- Relevant negative and edge cases derived from the specification

---

### Rule 3 — Include Cross-View Test Cases for Related Views

For every **Spec File** entry in the **Related Views** section:

1. Read the referenced spec file to understand its view ID, components, fields, validations, and flow.
2. Generate test cases that span both the related view and the current view, following the Test Context described in the relationship entry.
3. In cross-view test cases, prefix each field reference with its source view ID: `<<view-id>>.${field-name}`.
4. The test case must be fully self-contained — it must describe all steps from the related view setup through the final assertion in the current view.

For every **External Service** entry: do not generate test cases that directly test the external service. Instead, generate test cases that mock or stub the service and assert the expected behavior of the current view as a result.

---

### Rule 4 — Generate a Test Data Template Automatically

After generating all test cases, always produce a separate **Test Data Template** as a standalone document. This template must:

- Be fully decoupled from the test cases — it contains only data, never test logic
- Group all fields by their source view using `<<view-id>>` as a section header
- List every `${field-name}` referenced across all generated test cases under the correct view section
- Preserve the exact `${field-name}` identifiers — never rename or alias them
- Include a fill-in placeholder for each field value
- Be organized by test scenario so the user knows which values belong to which scenario

**Test Data Template format:**

```
# Test Data — <<current-view-name-uuid>>

## Scenario: (scenario name)

### <<current-view-name-uuid>>
- ${field-name}: (fill value here)
- ${field-name}: (fill value here)

### <<related-view-name-uuid>>
- ${field-name}: (fill value here)
- ${field-name}: (fill value here)

## Scenario: (scenario name)

### <<current-view-name-uuid>>
- ${field-name}: (fill value here)
```

---

### Rule 5 — Keep Test Cases and Test Data Independent

Test cases reference `${field-name}` placeholders. The test data template provides the concrete values that replace those placeholders at execution time. These two artifacts must never be merged. The user fills the test data template before running the tests — the test cases themselves never change.
