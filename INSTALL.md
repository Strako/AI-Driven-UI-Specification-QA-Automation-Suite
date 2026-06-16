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

## Option A — Install via Claude Code (Recommended)

**Step 1 — Add this repository as a plugin marketplace (one-time per machine):**

```bash
claude plugin marketplace add Strako/AI-Driven-UI-Specification-QA-Automation-Suite
```

**Step 2 — Install the plugin into your project:**

```bash
claude plugin install AI-Driven-UI-Specification
```

This automatically installs all agents, skills, hooks, settings, MCP config, and root files into your project.

---

## Option B — Manual Installation

If you cloned or downloaded this plugin package, copy files as follows:

```bash
# 1. Copy agents
cp agents/*.md .claude/agents/

# 2. Copy skills
cp -r skills/* .claude/skills/

# 3. Copy hooks (make sure they are executable)
cp hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh

# 4. Merge settings (or copy if .claude/settings.json does not exist yet)
cp settings.json .claude/settings.json

# 5. Copy MCP server config (or merge with existing .mcp.json)
cp .mcp.json .mcp.json

# 6. Copy root files
cp TEMPLATE.md vars.md user-guide.md README.md ./
```

> **If you already have a `.claude/settings.json`**, manually merge the `permissions.allow` entries and `hooks` blocks from `settings.json` into your existing file instead of overwriting it.

---

## Post-Installation Setup

### 1. Configure vars.md

Open `vars.md` at your project root and fill in your app's credentials:

```
BASE_URL = https://your-app.example.com
AUTH_EMAIL = admin@your-app.example.com
AUTH_PASSWORD = your-password
```

You can define any variable names — just reference them by name when invoking the agents.

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
