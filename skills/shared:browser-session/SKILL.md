# Skill: shared:browser-session

## Relay-Safe Browser Navigation (Shared Procedure)

This is the single canonical procedure for **navigating and snapshotting** with the
`playwright_headed` MCP server. Any skill that drives the browser **follows this file**
instead of calling `browser_navigate` / `browser_snapshot` ad-hoc, so navigation behaves
identically whether the MCP server was launched in the default standalone mode
(`--browser chrome`) or in **extension relay mode** (`--extension`). Current callers:

- `spec-wizard:auto-generate` — Phase 1 (navigate to and capture the target page)
- `test-execution:process` — Step 3 (navigate before each test case)
- `shared:account-identity` — Step D (opening the Yopmail second tab)

All tool calls use the prefix `mcp__plugin_AI-Driven-UI-Specification_playwright_headed__`.

---

### Why this procedure exists — the relay tab

When the MCP server is launched with `--extension`, Playwright does **not** own the
browser; it attaches to a real Chrome through the relay extension. That relay keeps a
permanent control tab open — its URL starts with `chrome-extension://` and contains
`connect.html`, and its title is **"Welcome"** (its snapshot reads `✅ "…" connected.`).

This relay tab is **not your page**. After any navigation — especially a cross-origin
redirect such as an auth bridge — the relay can re-assert its own control tab as the
"current" tab between your `browser_navigate` and your next `browser_snapshot`. A bare
snapshot then returns the "Welcome" page instead of the site you navigated to.

**The failure this prevents:** reading the relay page, concluding "navigation failed,"
and opening a fresh tab to retry — over and over, forever, while the real page is in fact
loaded and visible. If you ever find yourself about to open a new tab because a snapshot
"looks wrong," STOP — you are in this failure mode. Re-select the working tab instead
(Step 3), never open a new one.

In standalone mode there is no `chrome-extension://…/connect.html` tab, so the relay
branches below simply never fire and this procedure behaves like a plain navigate.

---

### Step 1 — Establish the working tab (once per session)

Do this the first time you touch the browser in a run, and remember the result:

1. `browser_tabs` with `action: "list"`.
2. Classify every tab by URL:
   - **Relay tab** — URL starts with `chrome-extension://` **and** contains `connect.html` (title "Welcome"). Never your working tab. Never navigate it, never close it, never snapshot it for content.
   - **Working tab** — any tab that is **not** a relay tab (your app tab, or a fresh `about:blank`).
3. Choose the working tab:
   - If exactly one non-relay tab exists → that is your working tab; `browser_tabs` `action: "select"` its index.
   - If several non-relay tabs exist → prefer one already on the app's origin; otherwise pick the first non-relay tab and select it.
   - If **no** non-relay tab exists → open **exactly one**: `browser_tabs` `action: "new"` (about:blank). This is now your working tab. **This is the only time you open a tab for navigation.**
4. Record the working tab's index. Note that indices can shift when tabs open/close — always re-identify the working tab by URL (non-relay, matching the app origin), not by a memorized absolute number.

---

### Step 2 — Navigate (relay-safe)

To go to a URL:

1. Make sure the working tab is selected (Step 1 / Step 3).
2. `browser_navigate` to the full URL.
3. If the URL is known to redirect (e.g. an auth bridge, SSO, a `302` you already
   observed), do **not** immediately snapshot. Instead `browser_wait_for` the expected
   final state — a URL fragment, a heading, or a known text on the destination page —
   giving the redirect chain time to settle. A generous timeout here is correct; the
   redirect hop is exactly when the relay grabs focus.
4. Proceed to Step 3 to read the page. **Never** call `browser_tabs action: "new"` as a
   way to "retry" a navigation.

---

### Step 3 — Focus the working tab, then snapshot (relay-safe read)

Every time you need to read the page (`browser_snapshot`, screenshot, or reading refs):

1. `browser_snapshot`.
2. Inspect the snapshot's **Page URL**:
   - If it is a real app URL → good, use it.
   - If it is the relay page (`chrome-extension://…/connect.html`, or the snapshot body
     is just `✅ "…" connected.`) → the relay stole focus. **Do not open a tab.** Recover:
     a. `browser_tabs` `action: "list"`.
     b. Find the working tab = the non-relay tab whose URL matches the app origin you
        navigated to (or the only non-relay tab).
     c. `browser_tabs` `action: "select"` that index.
     d. `browser_snapshot` again.
3. Repeat the list → select → snapshot recovery **at most 3 times**.
4. If after 3 attempts the snapshot still shows the relay page, **stop and report** —
   do not loop, do not open tabs. Use the caller's failure convention with reason:
   `"Playwright extension relay kept focus on its control tab (connect.html); the app tab could not be read. Confirm the relay Chrome extension is connected, or relaunch the MCP server without --extension."`

---

### Step 4 — Second tabs you genuinely need (e.g. Yopmail)

Some flows legitimately open a second tab (Yopmail verification, Step D of
`shared:account-identity`). In relay mode:

- The relay tab does not count as one of "your" tabs — ignore it when reasoning about
  which tab is which.
- **Select tabs by matching URL, never by a fixed absolute index** — the relay occupies
  an index and shifts the others. After `browser_tabs action: "new"`, confirm the new
  tab's URL via `list` before typing into it.
- When you switch back to the original working tab, re-identify it by URL per Step 3,
  then re-verify with a snapshot before continuing the flow.
- Close only the extra tab you opened (`action: "close"` on the tab you matched by URL) —
  never the relay tab.

---

### Tool reference

The installed `playwright_headed` MCP exposes a single tab-management tool with an
`action` parameter — use it for all tab operations:

- `browser_tabs` `action: "list"` — enumerate open tabs with their URLs
- `browser_tabs` `action: "select"` `index: N` — make tab N current
- `browser_tabs` `action: "new"` `url: "about:blank"` — open a new tab
- `browser_tabs` `action: "close"` `index: N` — close tab N

(Older docs referred to `browser_tab_new` / `browser_tab_select` / `browser_tab_close`;
the current server uses the single `browser_tabs` tool above.)
