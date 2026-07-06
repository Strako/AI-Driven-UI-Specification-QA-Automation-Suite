# Installation Guide — AI-Driven-UI-Specification

## Prerequisites

| Dependency | Minimum Version | Purpose |
|---|---|---|
| [Node.js](https://nodejs.org/) | v18+ | Runtime for `npx` and Playwright MCP server |
| [npm](https://www.npmjs.com/) | v9+ | Package manager (ships with Node.js) |
| [Python 3](https://www.python.org/) | v3.8+ | Used by pipeline hooks for JSON parsing |
| [Google Chrome](https://www.google.com/chrome/) | Latest stable | Browser used by Playwright MCP in headed mode |
| [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | Latest | Agent runtime |

---

## Install via Claude Code (the only supported method)

**Step 1 — Add this repository as a plugin marketplace (one-time per machine):**

```bash
claude plugin marketplace add Strako/AI-Driven-UI-Specification-QA-Automation-Suite
```

**Step 2 — Install the plugin into your project:**

```bash
claude plugin install AI-Driven-UI-Specification
```

This registers the plugin's agents, skills, hooks, and MCP servers with Claude Code. They run directly from the plugin's installed location (`${CLAUDE_PLUGIN_ROOT}`) — **never copy `agents/`, `skills/`, `hooks/`, or `settings.json` into your project's `.claude/` directory.** Doing so creates a stale fork that silently drifts from the plugin and breaks path resolution (agents look for their skill files via `${CLAUDE_PLUGIN_ROOT}`, which only resolves correctly for a properly installed plugin).

If you're contributing to or modifying this plugin's source, clone the repo and edit files under `agents/`, `skills/`, `hooks/` directly, then reinstall/reload the plugin so Claude Code picks up the change from the plugin's own directory — do not copy those files elsewhere.

---

## Post-Installation Setup

### 0. Create TEMPLATE.md

Every agent expects `TEMPLATE.md` (the canonical spec format) at your project root, alongside `vars.md`. Seed it once from the plugin's shipped example — this is a one-time content scaffold you're free to customize per project, unlike the plugin's agents/skills/hooks, which must always run from the plugin itself:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/TEMPLATE.md" ./TEMPLATE.md
```

### 1. Create vars.md

Create `vars.md` at your project root with your app's credentials:

```
BASE_URL = https://your-app.example.com
AUTH_EMAIL = admin@your-app.example.com
AUTH_PASSWORD = your-password
```

This is a project-owned file, not part of the plugin — you create and maintain it yourself. You can define any variable names — just reference them by name when invoking the agents.

### 2. (Optional) Figma access token

If you plan to use design comparison features, set your Figma personal access token in your shell profile:

```bash
# Add to ~/.zshrc or ~/.bashrc
export FIGMA_ACCESS_TOKEN=fig_xxxxxxxxxxxxx
```

Then reload: `source ~/.zshrc`

Generate a token at: **Figma → Settings → Personal access tokens**

### 3. Create a Platform directory

The pipeline stores specs and test artifacts under `Platform/` at your project root:

```bash
mkdir -p Platform
```

---

## Verify Installation

Open Claude Code in your project and run:

```
Which agents are available?
```

You should see: `spec-wizard-generate`, `spec-wizard-improve`, `spec-wizard-pipeline`, `qa-coordinator`, `test-generation`, `test-execution`, and `spec-wizard`.

---

## Quick Start

Read [user-guide.md](user-guide.md) for a complete step-by-step walkthrough from a live page URL to a full test execution report.
