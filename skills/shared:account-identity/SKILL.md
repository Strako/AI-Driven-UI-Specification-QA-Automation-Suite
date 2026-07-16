# Skill: shared:account-identity

## Persistent Test Identity & Yopmail Verification (Shared Procedure)

This is the single canonical procedure for creating a throwaway test account and
confirming it by email. Any skill that needs to do this **follows this file**
instead of keeping its own copy, so the identity format and the Yopmail steps
stay identical everywhere they're used. Current callers:

- `test-execution:process` — Step 1a (resolve identity) and Step 3.1a (OTP/confirmation)
- `spec-wizard:auto-generate` — Phase 1.1 (account creation before analyzing an authenticated page)

Callers keep their own decision logic (what counts as success, how to report a
failure, which test case or phase triggers this). Only the mechanics below —
detection, generation, form submission, Yopmail — are shared.

---

### When to use this procedure

Whenever a flow needs one or more credential variables from `vars.md` — an
email variable alone, or an email + password pair, under whatever variable
names the caller specifies (e.g. `AUTH_EMAIL` / `AUTH_PASSWORD`, or custom
names) — and:

- an account has to exist under those credentials before the caller can continue, and
- it isn't certain yet whether that account already exists.

---

### Step A — Detect placeholder vs. real values

Read the current value of each credential variable from `vars.md`. A variable
is **unset** if its value exactly matches one of:

- the literal seed placeholders shipped in `vars.md` (`your-login-email@example.com`, `your-login-password`), or
- an empty/blank value, or
- any other placeholder text the caller's own `vars.md` uses for that variable (e.g. a custom var seeded with `not-set`).

- **Unset → generate a new identity.** Continue to Step B.
- **Already a real value → reuse it as-is.** Do not regenerate or overwrite it. Skip straight to whatever the caller does with an existing identity (e.g. log in with it instead of signing up again).

This check must run independently for every credential variable in play — an
email-only flow only ever checks the email variable.

---

### Step B — Generate a new identity

1. Obtain a random suffix via `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate` (there is no `Bash`/`date` access in this flow): `() => Math.random().toString(36).slice(2, 8)` → e.g. `a8f3d1`.
2. **Email variable** → `qa-{random}@yopmail.com` (e.g. `qa-a8f3d1@yopmail.com`).
   - Always generate on the `@yopmail.com` domain — never invent or assume any other domain for a *generated* identity. This is what makes Step D (Yopmail verification) possible.
   - The only exception is Step A's "already a real value" branch: if `vars.md` already holds a real, non-placeholder email for that variable, that value's domain is used as-is and nothing is generated.
3. **Password variable**, only if the caller specified one (some signups/magic-link flows only need an email, with no password variable at all) → `Qa!{random}9` (guarantees upper+lower+digit+symbol).
4. Reuse the **same** random suffix for every variable generated in this call, so the email and password stay correlated to one throwaway identity.
5. Never hardcode a literal email or password anywhere in a prompt, skill file, or generated artifact. The only place a concrete value may ever be written is `vars.md` (Step E), and only the value generated in this step.

---

### Step C — Create the account

1. Using Playwright MCP tool calls only (`mcp__plugin_AI-Driven-UI-Specification_playwright_headed__*` — never programmatic Playwright), fill the target signup/registration form with the value(s) generated in Step B and submit.
2. If the flow requires an OTP, confirmation code, or confirmation link before the account is usable, run **Step D** now.
3. Judge success by the caller's own criteria (a test case's Expected Result, or — for spec generation — navigation away from the form / an authenticated destination page loading correctly).

---

### Step D — Yopmail verification (OTP / confirmation codes / confirmation links)

Never assume delivery, never fabricate a code — always verify through Yopmail.
The email to check is the one generated in Step B (or, if the caller is
verifying something other than the identity itself, whichever email value the
caller's own flow used earlier).

1. **Do not navigate away from the tab running the target flow.** Open a second tab: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_tab_new`.
2. In the new tab, navigate to `https://yopmail.com/en/`.
3. Snapshot, then type the local-part of the target email (the part before `@yopmail.com`) into Yopmail's inbox field and open the inbox.
4. Snapshot again and confirm the inbox header shows the exact expected address.
   - If it shows a different address, navigate back to `https://yopmail.com/en/` and re-enter the correct local-part. Retry up to 2 times.
   - If still mismatched after 2 retries, stop and report failure using the caller's own convention (e.g. `⚠️ BLOCKED` for test-execution) with reason: `"Yopmail displayed an unexpected inbox address and could not be corrected."`
5. Open the newest message addressed from the app under test. Either:
   - **Code/OTP**: read the code from the message body via snapshot, or
   - **Confirmation link**: click the link directly inside Yopmail's inline message preview — this triggers server-side confirmation regardless of which tab clicks it.
6. Switch back to the original tab: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_tab_select`.
7. Continue the caller's flow: type the code into the app's input and submit, or — if a link was clicked — proceed per the expected behavior (e.g. reload/navigate, since confirmation already completed server-side).
8. Close the Yopmail tab: `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_tab_close`, before continuing.

---

### Step E — Persist the identity

Only **after** Step C (and Step D, if it applied) has actually succeeded: use
`Edit` to overwrite the credential variable line(s) in `vars.md` with the
generated value(s) from Step B, so every later run — by any flow that reads
`vars.md` — reuses this same account instead of creating a new one.

- This is the only step in this procedure that ever writes to `vars.md`.
- If creation/confirmation did not succeed, leave the placeholders untouched so the next run retries with a fresh identity.
- Restoring the placeholder values in `vars.md` at any time forces the next run of any caller to generate a fresh identity.
