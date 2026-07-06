# Architecture Reference — Agents, Skills, and Hooks in Claude Code

This document is a deep-dive into the internals of the AI-Driven-UI-Specification plugin. It explains what agents, skills, and hooks are, how they work together, and how to modify or extend any part of the system.

If you just want to use the pipeline, read [user-guide.md](user-guide.md) instead. Come here when you want to understand why the system works the way it does, or when you want to fork and extend it.

---

## Plugin and Repository Structure

This repository is both the source code and the Claude Code plugin. The repo root is the plugin root — there is no nested source directory.

```
.                                    ← repo root = plugin root
├── .claude-plugin/
│   ├── plugin.json                  Plugin manifest: declares name, version, file mapping
│   └── marketplace.json             Marketplace catalog so users can add this repo as a source
├── package.json                     npm package metadata
├── settings.json                    Hook event configuration + MCP server permissions
├── .mcp.json                        Playwright and Figma MCP server definitions
│
├── agents/                          Agent definitions (one .md file per agent)
├── skills/                          Step-by-step execution instructions (one dir per skill)
├── hooks/                           Pipeline state machine (bash scripts)
│
├── TEMPLATE.md                      Canonical spec format — read by every agent
├── vars.md                          User-filled config: BASE_URL + credentials (test-execution and
│                                     spec-wizard-generate both persist a generated AUTH_EMAIL/
│                                     AUTH_PASSWORD here on first signup — see skills/shared:account-identity/)
├── user-guide.md                    End-user walkthrough
├── README.md                        Project overview and install instructions
├── INSTALL.md                       Detailed setup guide
└── personal-explanation.md          This file — architecture reference
```

When `claude plugin install` runs, it reads `.claude-plugin/plugin.json` and installs:
- `agents/*.md` → `.claude/agents/`
- `skills/**` → `.claude/skills/`
- `hooks/*.sh` → `.claude/hooks/` (made executable automatically)
- `settings.json` → merged into `.claude/settings.json`
- `.mcp.json` → merged into `.mcp.json`
- Root files → project root

The `Platform/` and `docs/` folders are **not** part of the plugin. The user creates `Platform/` themselves (`mkdir Platform`). The `docs/` folder is optional and user-managed — the plugin never touches it.

---

## System Flow Diagram

```mermaid
flowchart TD
    USER(["User"]) -->|"Invokes spec-wizard-generate"| SWG

    subgraph SPEC_CREATION["STAGE 1 - Spec Creation"]
        SWG[/"spec-wizard-generate\nAgent Opus"/]
        SWG -->|"Reads"| SKILL_AG["spec-wizard:auto-generate\nSKILL.md"]
        SKILL_AG -->|"Instructions"| SWG
        SWG -->|"MCP Tool Calls"| PW1["Playwright MCP headed"]
        PW1 -->|"DOM + Screenshots"| SWG
        SWG -->|"Spec in memory\n(Phase AUTO)"| REQ_PROMPT

        REQ_PROMPT{{"Requirements\nenrichment?"}}
        REQ_PROMPT -->|"file path"| REQ_FILE["Reads requirements file"]
        REQ_PROMPT -->|"docs"| REQ_DOCS["Scans docs/ folder\n(root = dir of vars.md)"]
        REQ_PROMPT -->|"skip"| WRITE_SPEC
        REQ_FILE -->|"Filters relevant\nRefines spec in memory"| WRITE_SPEC
        REQ_DOCS -->|"Filters relevant\nRefines spec in memory"| WRITE_SPEC

        WRITE_SPEC["Write tool →\nmodule-description.md"]
        WRITE_SPEC -->|"Writes enriched spec"| SPEC_FILE["module-description.md"]
    end

    SPEC_FILE -->|"PostToolUse Write"| HOOK_SPEC["pipeline-on-spec-created.sh"]
    HOOK_SPEC -->|"State: SPEC_AUTO_GENERATED"| STATE_FILE[".pipeline-state"]

    SWG -->|"Asks: improvement wizard?"| USER_CHOICE{{"yes / no"}}
    USER_CHOICE -->|"yes"| SWI
    USER_CHOICE -->|"no"| SWP

    subgraph SPEC_IMPROVE["STAGE 1b - Spec Improvement"]
        SWI[/"spec-wizard-improve\nAgent Opus"/]
        SWI -->|"Reads"| SKILL_IMP["spec-wizard:improve\nSKILL.md"]
        SKILL_IMP -->|"9 interactive sections"| SWI
        SWI -->|"Overwrites"| SPEC_FILE
    end

    SWI --> SWP

    subgraph PIPELINE_OFFER["STAGE 1c - Pipeline Offer"]
        SWP[/"spec-wizard-pipeline\nAgent Opus"/]
        SWP -->|"Reads"| SKILL_PO["spec-wizard:pipeline-offer\nSKILL.md"]
        SKILL_PO -->|"Summary + Offer"| SWP
    end

    SWP -->|"Run QA Pipeline?"| PIPELINE_CHOICE{{"yes / no"}}
    PIPELINE_CHOICE -->|"no"| DONE_SPEC(["Spec complete"])
    PIPELINE_CHOICE -->|"yes"| QAC

    subgraph QA_PIPELINE["STAGE 2 - QA Pipeline"]
        QAC[/"qa-coordinator\nAgent Opus"/]
        QAC -->|"Dispatch sub-agent"| TG

        subgraph TEST_GEN["Test Generation"]
            TG[/"test-generation\nAgent Sonnet"/]
            TG -->|"Reads"| SKILL_TG["test-generation:process\nSKILL.md"]
            TG -->|"Assigns Severity\n(Critical/Mid/Low)"| TC
            TG -->|"Write"| TC["test-cases.md"]
            TG -->|"Write"| TD["test-data.md"]
        end
    end

    TC -->|"PostToolUse Write"| HOOK_TG["pipeline-on-tests-generated.sh"]
    HOOK_TG -->|"State: GENERATION_COMPLETE"| STATE_FILE

    QAC -->|"PAUSE"| USER_FILL(["User fills test-data.md"])
    USER_FILL -->|"done / ready"| HOOK_PROMPT["pipeline-on-user-prompt.sh"]
    HOOK_PROMPT -->|"State: TEST_DATA_READY"| QAC

    QAC -->|"Attempts dispatch"| HOOK_GATE{"PreToolUse:\npipeline-on-execution-dispatch.sh"}
    HOOK_GATE -->|"auto mode, or\nEXECUTION_LEVEL known"| TE
    HOOK_GATE -->|"blocked: not auto mode,\nno level yet"| ASK_LEVEL(["qa-coordinator asks:\n1 Critical / 2 Critical+Mid / 3 All"])
    ASK_LEVEL --> HOOK_PROMPT
    HOOK_PROMPT -->|"State: AWAITING_EXECUTION_LEVEL\n→ resolved → TEST_DATA_READY"| QAC
    QAC -->|"Retry dispatch\nwith EXECUTION_LEVEL"| HOOK_GATE

    subgraph TEST_EXEC["STAGE 3 - Test Execution"]
        TE[/"test-execution\nAgent Sonnet"/]
        TE -->|"Reads"| SKILL_TE["test-execution:process\nSKILL.md"]
        TE -->|"Step 1a"| AUTH_ID{"AUTH_EMAIL/PASSWORD\nin vars.md?"}
        AUTH_ID -->|"real values"| REUSE_ID["Reuse persisted identity\n(signup TC → ⚠️ BLOCKED)"]
        AUTH_ID -->|"placeholders"| GEN_ID["Generate qa-{random}@yopmail.com\nvia browser_evaluate"]
        GEN_ID -->|"signup TC → ✅ PASS"| PERSIST_ID["Write → vars.md\n(AUTH_EMAIL/AUTH_PASSWORD)"]
        TE -->|"Filters by EXECUTION_LEVEL\nvs. Severity"| SKIP_FILTER{"Severity meets\nlevel?"}
        SKIP_FILTER -->|"no"| SKIPPED_TC(["⏭ SKIPPED\n(never executed)"])
        SKIP_FILTER -->|"yes"| PW2
        TE -->|"MCP Tool Calls"| PW2["Playwright MCP headed"]
        TE -->|"Step 3.1a: OTP/confirmation"| YOPMAIL["2nd tab →\nyopmail.com/en/"]
        TE -->|"Design Comparison"| DESIGN_MCP{"Design Reference?"}
        DESIGN_MCP -->|"Figma URL"| FIGMA_MCP["Figma MCP"]
        DESIGN_MCP -->|"Pencil name"| PENCIL_MCP["Pencil MCP"]
        TE -->|"Write"| REPORT["test-report-module.md"]
        TE -->|"Write"| SCREENSHOTS["TC-screenshots.png"]
    end

    REPORT -->|"PostToolUse Write"| HOOK_RPT["pipeline-on-report-written.sh"]
    HOOK_RPT -->|"State: EXECUTION_COMPLETE"| STATE_FILE

    QAC --> DONE_PIPELINE(["Pipeline complete — report delivered"])
```

> **Note on `AUTH_ID` / `GEN_ID` / `PERSIST_ID` / `YOPMAIL`.** These four nodes are drawn once, under `test-execution`, but they are not test-execution-specific logic — they're the shared `skills/shared:account-identity/SKILL.md` procedure (Steps A–E). `spec-wizard-generate` walks through the exact same four nodes in its own Phase 1.1b, triggered when its Auth answer is "new account" instead of by a signup test case reaching PASS/BLOCKED. Both agents read the shared skill file rather than keeping their own copy of the generation formula or the Yopmail steps, so the diagram's `AUTH_ID → GEN_ID → PERSIST_ID` / `YOPMAIL` sub-flow applies unchanged to either caller — only what triggers entry into it, and what "success" means at the end, differs per agent.

---

## 1. What is an Agent?

An **Agent** is an isolated Claude instance with its own context window, system prompt, tool access, and permissions. When the main Claude session encounters a task that matches an agent's description, it delegates the work to that agent, which operates independently and returns only the result.

### Key characteristics

- **Isolated context**: each agent has its own context window — it cannot see the main conversation history
- **Own system prompt**: defined in the markdown body of the agent's `.md` file
- **Restricted tools**: you can limit which tools it can use (Read, Write, Bash, MCP tools, etc.)
- **Configurable model**: can use a different model than the main session (opus, sonnet, haiku)
- **Independent permissions**: can have its own permission mode

### Syntax — Agent definition file

Agents are defined as markdown files with YAML frontmatter in `agents/` (in the plugin repo) or `.claude/agents/` (in a user's project after installation):

```markdown
---
name: my-agent
description: Description of when to use this agent. Claude uses this to decide when to delegate.
model: claude-sonnet-4-6
color: "#16A34A"
tools: Read, Write, Bash, Glob, Grep, mcp__plugin_AI-Driven-UI-Specification_playwright_headed
---

This is the agent's system prompt.
Everything here is what the agent "knows" and follows as instructions.
```

### Frontmatter fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Unique kebab-case identifier |
| `description` | Yes | When Claude should delegate to this agent |
| `tools` | No | Allowed tools (inherits all if omitted) |
| `disallowedTools` | No | Explicitly denied tools |
| `model` | No | Model: `sonnet`, `opus`, `haiku`, or full model ID |
| `permissionMode` | No | `default`, `acceptEdits`, `auto`, or `bypassPermissions` |
| `maxTurns` | No | Maximum turns before stopping |
| `color` | No | Background color in the UI |

### How an agent dispatches sub-agents

In this project, `qa-coordinator` dispatches `test-generation` and `test-execution` using the `Agent()` tool declaration in its frontmatter:

```markdown
---
name: qa-coordinator
tools: Read, Glob, Agent(test-generation, test-execution)
---
```

The `Agent(test-generation, test-execution)` field is what permits this agent to invoke those two as sub-agents. Sub-agents are started by the orchestrator using the Agent tool — each runs in its own isolated context and returns a result. This means the orchestrator cannot pause a dispatched sub-agent mid-run to ask the human a question — only the orchestrator itself (a live, turn-by-turn conversation) can do that. `pipeline-on-execution-dispatch.sh` exploits the one place this constraint can still be worked around: a `PreToolUse` hook fires on the Agent-tool call itself, *before* the sub-agent starts, so it can block the call and hand the orchestrator a reason to ask first — see the [Execution Roughness Gate example](#example-from-this-project--pipeline-on-execution-dispatchsh-pretooluse-blocking) below.

### How agents are invoked

1. **Automatically**: Claude decides to delegate based on the `description` field
2. **Explicitly**: the user switches to the agent or says "use spec-wizard-generate"
3. **From another agent**: using `Agent(name)` in the tools field and calling the Agent tool
4. **As the main session**: `claude --agent my-agent`

---

## 2. What is a Skill?

A **Skill** is a `SKILL.md` file with step-by-step instructions that extend Claude's capabilities. Think of it as a playbook — a precise set of instructions that Claude loads into its context and follows exactly. Unlike `CLAUDE.md` (which is always in context), a skill is loaded only when needed.

### Key characteristics

- **On-demand loading**: the skill's content only enters context when the agent reads it
- **Detailed instructions**: can contain complex multi-step procedures
- **No independent execution**: skills don't run anything on their own — the agent reads them and acts on them
- **Argument support**: supports `$ARGUMENTS`, `$0`, `$1`, etc.

### Skill location

In the plugin repo:
```
skills/
└── my-skill:process/
    └── SKILL.md
```

After installation in a user's project:
```
.claude/skills/
└── my-skill:process/
    └── SKILL.md
```

The subdirectory naming convention `skill-name:variant` is a colon-separated namespace. For example, `spec-wizard:auto-generate` and `spec-wizard:improve` are two variants of the spec-wizard skill family.

### How agents use skills

Every agent in this project loads its skill at startup using the `Read` tool:

```markdown
## Skill Loading

Before doing anything else, read your skill file:

1. Use the `Read` tool to load: `.claude/skills/my-skill:process/SKILL.md`
   - If PROJECT_ROOT was provided: `{PROJECT_ROOT}/.claude/skills/...`
   - If not: use Glob to find `vars.md` and derive the project root
2. Follow every step in the skill file completely and in order.
```

This pattern — agent reads skill, then executes its steps — is how all seven agents in this plugin work.

### Difference: Skill vs Agent

| Aspect | Skill | Agent |
|---|---|---|
| Context | Loaded IN the current conversation | Has its OWN isolated context |
| Intelligence | No — it's text that a model reads | Yes — it's a full LLM instance |
| Tools | Uses the session's tools | Has its own defined tools |
| Interactivity | Can be multi-turn in the same conversation | Works autonomously |
| Ideal use | Detailed procedures the agent must follow | Isolated tasks that produce significant output |

---

## 3. What is a Hook?

A **Hook** is a shell script that runs automatically at specific points in the Claude Code lifecycle. Hooks are **deterministic** — they always execute when the triggering condition is met, regardless of what the LLM decides.

### Key characteristics

- **Deterministic**: always execute when the event fires — not subject to LLM judgment
- **Event-driven**: triggered at specific lifecycle moments (after Write, before a tool, on user message)
- **Communicate via stdin/stdout/stderr**: receive JSON on stdin, return decisions via exit code or context via stdout
- **Can block actions**: exit code 2 blocks the action and sends stderr as feedback to Claude
- **Can inject context**: stdout in certain events is added to Claude's context window
- **Run in parallel**: multiple hooks for the same event run simultaneously

### Hook configuration in settings.json

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/pipeline-on-spec-created.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/pipeline-on-user-prompt.sh"
          }
        ]
      }
    ]
  }
}
```

The commands use project-relative paths (`.claude/hooks/...`), which works in any project once the hooks are installed.

### Available events

| Event | When it fires | Matcher filters by |
|---|---|---|
| `SessionStart` | Session start or resume | `startup`, `resume`, `clear`, `compact` |
| `UserPromptSubmit` | When the user sends a message | (no matcher) |
| `PreToolUse` | Before a tool executes | Tool name: `Bash`, `Edit\|Write`, `mcp__.*`, `Agent` |
| `PostToolUse` | After a tool executes | Tool name |
| `PermissionRequest` | When a permission dialog appears | Tool name |
| `Stop` | When Claude finishes responding | (no matcher) |
| `SubagentStart` | When a sub-agent is created | Agent type |
| `SubagentStop` | When a sub-agent finishes | Agent type |

### Exit codes

| Exit Code | Meaning |
|---|---|
| `0` | Action permitted. stdout is added to context (in certain events). |
| `2` | Action blocked. stderr is sent as feedback to Claude. |
| Other | Error — action continues, warning shown in transcript. |

### Hook portability — how the scripts resolve paths

The five hooks in this plugin resolve the project root without hardcoding any paths, using one of two equivalent patterns:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="$PROJECT/.claude/.pipeline-state"
```

Because hooks are always installed at `.claude/hooks/`, `$SCRIPT_DIR` resolves to `<project>/.claude/hooks` and `$PROJECT` resolves two levels up to the project root. `pipeline-on-spec-created.sh` uses this form. The other four (`pipeline-on-tests-generated.sh`, `pipeline-on-report-written.sh`, `pipeline-on-user-prompt.sh`, `pipeline-on-execution-dispatch.sh`) rely on `PROJECT="${PWD}"` instead — equally portable here since Claude Code always runs hooks with the project root as the working directory. Either way, the same script works correctly in any project.

### Example — `pipeline-on-spec-created.sh`

```bash
#!/bin/bash
# Fires after every Write tool call.
# Detects when a spec file is written inside Platform/ and updates pipeline state.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

[[ -z "$FILE" ]] && exit 0

# Match: Platform/**/*-description.md
if [[ "$FILE" == "$PROJECT/Platform/"* ]] && \
   [[ "$FILE" =~ \-description\.md$ ]]; then

  MODULE_DIR=$(dirname "$FILE")
  MODULE=$(basename "$MODULE_DIR")

  printf "SPEC_AUTO_GENERATED\n%s\n%s\n" "$MODULE" "$FILE" > "$STATE_FILE"
fi

exit 0
```

The JSON received on stdin for a `PostToolUse` Write event looks like:

```json
{
  "session_id": "abc123",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/path/to/project/Platform/Login/login-description.md",
    "content": "..."
  }
}
```

### Example — Hook that injects context (UserPromptSubmit)

```bash
#!/bin/bash
# Detects when the user says "done" and injects a dispatch instruction into Claude's context.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="$PROJECT/.claude/.pipeline-state"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('prompt','').lower())" \
  2>/dev/null || echo "")

CURRENT_STATE=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || echo "")

if [[ "$CURRENT_STATE" == "GENERATION_COMPLETE" ]] && \
   echo "$PROMPT" | grep -qiE "(done|ready|filled)"; then
  # stdout is injected into Claude's context
  cat <<MSG
The user has confirmed test data is ready.
Dispatch the test-execution agent now.
MSG
fi

exit 0
```

### Example — Hook that blocks an action (PreToolUse)

```bash
#!/bin/bash
# Blocks writes to .env files.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" \
  2>/dev/null || echo "")

if [[ "$FILE_PATH" == *".env"* ]]; then
  echo "Blocked: Cannot modify .env files" >&2
  exit 2  # EXIT 2 = BLOCK
fi

exit 0  # EXIT 0 = ALLOW
```

### Example from this project — `pipeline-on-execution-dispatch.sh` (PreToolUse, blocking)

This hook gates `qa-coordinator`'s attempt to dispatch `test-execution`. It is the only hook in this plugin that reads `permission_mode` — that field is only present in `PreToolUse` payloads, not in `PostToolUse` or `UserPromptSubmit` ones, and **not at all** in `SubagentStart` (which also cannot block — exit code 2 there only prints a warning, the sub-agent spawns regardless). This is why the gate lives here instead of on `SubagentStart`, even though conceptually it's about "the test-execution stage starting":

```bash
PERMISSION_MODE=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('permission_mode',''))")

[[ "$PERMISSION_MODE" == "auto" ]] && exit 0   # auto mode: let it run everything

# Not auto mode and no EXECUTION_LEVEL yet — block and tell qa-coordinator to ask.
printf "AWAITING_EXECUTION_LEVEL\n%s\n%s\n" "$MODULE" "$MODULE_DIR" > "$STATE_FILE"
echo "Ask the user: 1 Critical / 2 Critical+Mid / 3 All, then retry with EXECUTION_LEVEL set." >&2
exit 2
```

`qa-coordinator` itself never sees `permission_mode` directly — the hook is the only thing that can, and it hands the decision back as plain-English feedback the agent then acts on conversationally, the same way it already reacts to the `test-data.md` pause instructions.

---

## 4. How They Work Together — Agent + Skill + Hook

### The mental model

Think of them as three layers of the system:

```
┌─────────────────────────────────────────────────────────────────┐
│  HOOKS (Infrastructure layer)                                   │
│  • Deterministic — always execute when the event fires          │
│  • Observe system events (file writes, user messages)           │
│  • Can block, inject context, or update state                   │
│  • NO intelligence — pure shell scripts                         │
└─────────────────────────────────────────────────────────────────┘
         ▲ fire when events occur ▲
         │                         │
┌─────────────────────────────────────────────────────────────────┐
│  AGENTS (Orchestration layer)                                   │
│  • Isolated Claude instances with their own context             │
│  • Decide what to do based on their system prompt               │
│  • Can dispatch other agents (sub-agents)                       │
│  • Use tools (Read, Write, Bash, MCP tools)                     │
│  • Their actions TRIGGER hooks                                  │
└─────────────────────────────────────────────────────────────────┘
         ▲ load and follow ▲
         │                   │
┌─────────────────────────────────────────────────────────────────┐
│  SKILLS (Knowledge layer)                                       │
│  • Step-by-step instructions that agents follow                 │
│  • Loaded into the agent's context when needed                  │
│  • Define the "how" — the exact procedure                       │
│  • Do NOT execute anything by themselves                        │
│  • The playbook that the agent reads and acts on                │
└─────────────────────────────────────────────────────────────────┘
```

### Analogy

| Concept | Analogy |
|---|---|
| **Agent** | A specialist employee with their own desk and tools |
| **Skill** | The procedure manual the employee reads and follows |
| **Hook** | The building's alarm system — fires automatically when something happens |

### Detailed execution trace

Here is exactly what happens when a user says "Create a spec for /dashboard":

```
1. USER → "Create a spec for /dashboard"
   │
   ├── [AGENT] spec-wizard-generate activates
   │   │
   │   ├── [SKILL] Reads .claude/skills/spec-wizard:auto-generate/SKILL.md
   │   │   └── Now knows exactly what to do (phases 0 → AUTO → REQUIREMENTS → Write)
   │   │
   │   ├── [AGENT] Phase 0: Collects inputs from user
   │   ├── [AGENT] Reads vars.md → extracts BASE_URL + credentials
   │   ├── [AGENT] Phase 1: Navigates with Playwright MCP
   │   │   └── browser_navigate → browser_snapshot → browser_take_screenshot
   │   ├── [AGENT] Phase AUTO: Generates complete spec IN MEMORY
   │   │
   │   ├── [AGENT] Phase REQUIREMENTS: Requirements enrichment
   │   │   └── Asks user: "file path / docs / skip?"
   │   │
   │   │   ├── USER → "/path/to/requirements.md" (or "docs")
   │   │   │   ├── [AGENT] Reads the file (Read tool)
   │   │   │   │   If "docs": locates vars.md via Glob → its parent dir is project root
   │   │   │   │   → scans {root}/docs/*.md and *.csv
   │   │   │   ├── [AGENT] Filters requirements relevant to this module
   │   │   │   └── [AGENT] Refines spec IN MEMORY (does not write yet)
   │   │   │
   │   │   └── USER → "skip" → continues without changes
   │   │
   │   └── [AGENT] Write → Platform/Dashboard/dashboard-description.md
   │       │    (enriched spec)
   │       │
   │       └── [HOOK fires] pipeline-on-spec-created.sh
   │           └── Detects *-description.md written under Platform/
   │           └── Writes "SPEC_AUTO_GENERATED" to .pipeline-state
   │
   ├── [AGENT] Asks: "Improvement wizard?"
   │   │
   │   └── USER → "no"
   │       │
   │       └── [HOOK fires] pipeline-on-user-prompt.sh
   │           └── Reads .pipeline-state → state = SPEC_AUTO_GENERATED
   │           └── Detects "no" → updates state to PIPELINE_OFFER_REQUESTED
   │
   ├── [AGENT] spec-wizard-pipeline activates
   │   ├── [SKILL] Reads .claude/skills/spec-wizard:pipeline-offer/SKILL.md
   │   └── Reads spec, shows summary, asks "Run QA Pipeline?"
   │
   └── USER → "yes"
       │
       ├── [AGENT] qa-coordinator activates
       │   │
       │   ├── [AGENT dispatches] test-generation (sub-agent)
       │   │   ├── [SKILL] Reads .claude/skills/test-generation:process/SKILL.md
       │   │   ├── [AGENT] Reads spec (never vars.md), generates test cases
       │   │   │   └── Navigation stays symbolic: <<view-id>> / {{BASE_URL}} — BASE_URL
       │   │   │       is never resolved here, so the same file works in any environment
       │   │   ├── [AGENT] Assigns Severity (Critical/Mid/Low) to every test case
       │   │   ├── [AGENT] Write → test-cases.md
       │   │   │   └── [HOOK fires] pipeline-on-tests-generated.sh
       │   │   │       └── State → GENERATION_COMPLETE
       │   │   └── [AGENT] Write → test-data.md
       │   │       └── Reports SEVERITY_BREAKDOWN (Critical/Mid/Low counts) in its summary
       │   │
       │   ├── [AGENT] qa-coordinator PAUSES
       │   │   └── "Fill test-data.md and confirm when ready"
       │   │
       │   ├── USER → "done"
       │   │   └── [HOOK fires] pipeline-on-user-prompt.sh
       │   │       └── State = GENERATION_COMPLETE + "done" detected
       │   │       └── State → TEST_DATA_READY
       │   │       └── stdout: "Dispatch test-execution agent"
       │   │           (this text is injected into Claude's context)
       │   │
       │   ├── [AGENT attempts dispatch] test-execution (sub-agent)
       │   │   └── [HOOK fires] pipeline-on-execution-dispatch.sh (PreToolUse)
       │   │       ├── Reads permission_mode from the hook payload
       │   │       ├── auto mode, or EXECUTION_LEVEL already in the prompt → exit 0, dispatch proceeds
       │   │       └── otherwise → State → AWAITING_EXECUTION_LEVEL, exit 2 (BLOCKED)
       │   │           │
       │   │           ├── [AGENT] qa-coordinator asks: "1 Critical / 2 Critical+Mid / 3 All"
       │   │           │
       │   │           └── USER → "2"
       │   │               └── [HOOK fires] pipeline-on-user-prompt.sh
       │   │                   └── State = AWAITING_EXECUTION_LEVEL + "2" detected
       │   │                   └── State → TEST_DATA_READY
       │   │                   └── stdout: "Retry dispatch with EXECUTION_LEVEL = 2"
       │   │                       (agent retries the Agent-tool call — hook now allows it through)
       │   │
       │   └── [AGENT dispatches] test-execution (sub-agent)
       │       ├── [SKILL] Reads .claude/skills/test-execution:process/SKILL.md
       │       ├── [AGENT] Reads vars.md → this is the ONLY step in the pipeline
       │       │   where BASE_URL is resolved into a concrete domain
       │       ├── [AGENT] Step 1a — resolves AUTH_EMAIL/AUTH_PASSWORD:
       │       │   ├── Real values already in vars.md → reuse; a signup TC for
       │       │   │   that same account is marked ⚠️ BLOCKED (avoid duplicate signup)
       │       │   └── Still placeholders → generates qa-{random}@yopmail.com +
       │       │       password via browser_evaluate; persisted to vars.md only
       │       │       after the signup TC reaches ✅ PASS
       │       ├── [AGENT] Captures EXECUTION_STARTED timestamp via
       │       │   mcp__plugin_AI-Driven-UI-Specification_playwright_headed__browser_evaluate (no Bash/date available)
       │       ├── [AGENT] Hydrates test cases — ${field-name} → test data value,
       │       │   <<view-id>> / {{BASE_URL}} → real URL from vars.md,
       │       │   {{AUTH_EMAIL}} / {{AUTH_PASSWORD}} → identity from Step 1a
       │       ├── [AGENT] Filters by EXECUTION_LEVEL vs. each case's Severity
       │       │   └── Excluded cases marked ⏭ SKIPPED — never executed
       │       ├── [AGENT] Executes each remaining test via Playwright MCP
       │       │   └── navigate → snapshot → type → click → timestamped screenshot
       │       │       (captured for both ✅ PASS and ❌ FAIL; ⚠️ BLOCKED/⏭ SKIPPED have none)
       │       │   └── Step 3.1a — any OTP/confirmation step opens a second tab,
       │       │       checks the address on https://yopmail.com/en/, retrieves the
       │       │       code or clicks the confirmation link, then switches back
       │       ├── [AGENT] Design Comparison (if TC-DC exists):
       │       │   ├── Figma URL → uses Figma MCP to retrieve design
       │       │   └── Pencil name → uses Pencil MCP to retrieve design
       │       ├── [AGENT] Captures EXECUTION_COMPLETED timestamp
       │       ├── [AGENT] Write → test-report-dashboard.md
       │       │   │        (includes execution level, skipped tests, execution window)
       │       │   └── [HOOK fires] pipeline-on-report-written.sh
       │       │       └── State → EXECUTION_COMPLETE
       │       └── [AGENT] Write → TC-*-{timestamp}.png (screenshots)
       │
       └── [AGENT] qa-coordinator delivers final report
           └── "✅ QA Pipeline Complete"
```

---

## 5. The Pipeline State Machine

The hooks implement a **state machine** using a `.pipeline-state` file at `.claude/.pipeline-state`. This lets multiple agents coordinate across time without any single agent needing to "remember" the full pipeline state — the state is persisted on disk between turns.

```mermaid
stateDiagram-v2
    [*] --> REQUIREMENTS_ENRICHMENT : spec-wizard-generate generates spec in memory
    note right of REQUIREMENTS_ENRICHMENT
        Agent asks user: file path / docs / skip.
        Happens BEFORE writing to disk.
        Does NOT create a .pipeline-state entry.
    end note
    REQUIREMENTS_ENRICHMENT --> SPEC_AUTO_GENERATED : enriched spec written to disk
    SPEC_AUTO_GENERATED --> WIZARD_REQUESTED : user says "yes" (improve)
    SPEC_AUTO_GENERATED --> PIPELINE_OFFER_REQUESTED : user says "no" (skip)
    WIZARD_REQUESTED --> WIZARD_COMPLETE : spec-wizard-improve saves spec
    WIZARD_COMPLETE --> GENERATION_COMPLETE : test-generation writes test-cases.md
    PIPELINE_OFFER_REQUESTED --> GENERATION_COMPLETE : test-generation writes test-cases.md
    GENERATION_COMPLETE --> TEST_DATA_READY : user says "done" / "ready"
    TEST_DATA_READY --> EXECUTION_DISPATCH_ATTEMPTED : qa-coordinator attempts Agent-tool dispatch
    note right of EXECUTION_DISPATCH_ATTEMPTED
        pipeline-on-execution-dispatch.sh (PreToolUse) checks permission_mode.
        Not a .pipeline-state entry — it's the moment the dispatch is attempted.
    end note
    EXECUTION_DISPATCH_ATTEMPTED --> EXECUTION_COMPLETE : auto mode, or EXECUTION_LEVEL already known — dispatch allowed, test-execution writes test-report
    EXECUTION_DISPATCH_ATTEMPTED --> AWAITING_EXECUTION_LEVEL : not auto mode, no level yet — dispatch blocked (exit 2)
    AWAITING_EXECUTION_LEVEL --> TEST_DATA_READY : user answers 1 / 2 / 3 — retry dispatch with EXECUTION_LEVEL set
    EXECUTION_COMPLETE --> [*]
```

**How the state machine works:**

1. **Hooks OBSERVE** — each hook reads the current state from `.pipeline-state`
2. **Hooks UPDATE** — when they detect a relevant event, they write the new state
3. **Hooks INJECT** — in certain states, they write to stdout, which Claude Code injects into the agent's context as additional instructions
4. **Agents don't know about hooks** — agents follow their skills; hooks coordinate transitions invisibly between them

**Why use hooks instead of having the agent remember:**

- **Reliability**: hooks are deterministic — they always execute
- **Decoupling**: each agent is independent and doesn't need to know the full pipeline
- **Persistence**: state survives across sessions (it's a file on disk)
- **Simplicity**: each agent only knows its own task

---

## 6. Comparison Table

| Aspect | Agent | Skill | Hook |
|---|---|---|---|
| **What it is** | Isolated Claude instance | Instructions file | Automatic shell script |
| **Intelligence** | Yes — full LLM | No — text a model reads | No — deterministic code |
| **When it runs** | When Claude delegates or user invokes | When an agent loads it with Read | When the lifecycle event fires |
| **Context** | Own isolated context | Loaded IN the agent's context | No Claude context |
| **Can use tools** | Yes (Read, Write, Bash, MCP, etc.) | No — the agent uses tools | No — only shell commands |
| **Can make decisions** | Yes — reasons and decides | No — only provides instructions | Binary: allow/block |
| **Location in repo** | `agents/*.md` | `skills/<name>/SKILL.md` | `hooks/*.sh` |
| **Location in project** | `.claude/agents/*.md` | `.claude/skills/<name>/SKILL.md` | `.claude/hooks/*.sh` |
| **Example** | `qa-coordinator` orchestrates pipeline | `test-execution:process` defines 6 steps | `pipeline-on-spec-created.sh` detects writes |

---

## 7. Design Comparison — How It Works

Design comparison is an optional feature that compares the live web page against the original design (Figma or Pencil) and produces a discrepancy report.

> **Two different "severities" exist in this system — don't conflate them.** A test case's `Severity` (Critical/Mid/Low, assigned by `test-generation`) drives the execution roughness gate below. A discrepancy's severity (Critical/Major/Minor/Cosmetic, assigned by `test-execution` during design comparison) only classifies visual differences within the DESIGN COMPARISON report section. A Design Comparison test case is always test-case-`Severity` Critical, regardless of how many or how few discrepancy-severity issues it finds.

```
1. User provides a "Design Reference" when creating the spec
   (Figma frame URL or Pencil slide name)

2. spec-wizard-generate saves it in the spec's Screen Identification:
   "Pencil slide name / Figma frame URL: <value>"

3. test-generation detects the field and generates TC-DC-01
   (a test case of type Design Comparison)

4. test-execution runs TC-DC-01:
   a. Navigates to the page and takes a screenshot
   b. Retrieves the original design:
      - Figma URL → mcp__claude_ai_Figma__get_design_context or mcp__plugin_AI-Driven-UI-Specification_figma__get_node
      - Pencil name → mcp__pencil__batch_get
   c. Compares structure, typography, colors, spacing, components, images/icons
   d. Classifies discrepancies by severity: Critical / Major / Minor / Cosmetic
   e. Documents findings in the DESIGN COMPARISON report section

5. TC-DC result:
   ✅ PASS  — zero Critical or Major discrepancies
   ❌ FAIL  — one or more Critical or Major discrepancies
   ⚠️ BLOCKED — design reference could not be retrieved
```

---

## 8. How to Fork and Extend

### Forking the plugin

```bash
git clone https://github.com/Strako/AI-Driven-UI-Specification-QA-Automation-Suite.git my-fork
cd my-fork
```

### Modifying an agent

Open `agents/{agent-name}.md`. The frontmatter controls the model, tools, and behavior. The markdown body is the system prompt — edit it to change what the agent does or knows.

```markdown
---
name: spec-wizard-generate
model: claude-opus-4-6   ← change model here
tools: Read, Write, Bash, Glob, Grep, mcp__plugin_AI-Driven-UI-Specification_playwright_headed
---

... system prompt here — edit to change agent behavior ...
```

### Modifying a skill

Open `skills/{skill-name}/SKILL.md`. Skills are plain markdown with step-by-step instructions. The agents follow them literally — add, remove, or reorder steps to change execution behavior.

### Adding a new agent

1. Create `agents/my-new-agent.md`:

```markdown
---
name: my-new-agent
description: What this agent does and when Claude should use it.
model: claude-sonnet-4-6
color: "#4a90d9"
tools: Read, Write, Glob
---

Your system prompt here.

## Skill Loading

Before doing anything else, read your skill file:
1. Use the `Read` tool to load: `.claude/skills/my-new-agent:process/SKILL.md`
2. Follow every step completely and in order.
```

2. Create `skills/my-new-agent:process/SKILL.md` with the execution steps.

3. Update `package.json` version (semantic versioning) and push.

### Adding a new hook

1. Create `hooks/my-hook.sh`:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INPUT=$(cat)
# ... your logic ...
exit 0
```

2. Add it to `settings.json` under the appropriate event:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/my-hook.sh" }
        ]
      }
    ]
  }
}
```

3. Hooks are installed executable by the plugin installer. If installing manually: `chmod +x .claude/hooks/my-hook.sh`.

### Releasing an update

```bash
# Bump version in .claude-plugin/plugin.json
git add .
git commit -m "feat: describe your change"
git push

# Users update with:
claude plugin update AI-Driven-UI-Specification
```

---

## 9. References

- [Claude Code — Sub-agents Documentation](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Claude Code — Hooks Guide](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Claude Code — Skills Documentation](https://docs.anthropic.com/en/docs/claude-code/skills)
- [Claude Code — MCP Configuration](https://docs.anthropic.com/en/docs/claude-code/mcp)
