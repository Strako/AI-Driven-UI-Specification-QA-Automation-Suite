#!/usr/bin/env python3
"""
PIPELINE HOOK LOGIC — enforce that test-execution's report is really on disk.

Invoked by pipeline-verify-report.sh on SubagentStop (agent type: test-execution)
and, defensively, on every Stop. Reads the hook JSON from stdin (session_id,
transcript_path, stop_hook_active), then:

  1. Scans the transcript for the LAST ---EXECUTION-COMPLETE--- signal block
     the test-execution skill (skills/test-execution:process/SKILL.md, Step 6)
     requires the agent to emit. No signal found → this stop is unrelated to
     test-execution → no-op.
  2. Resolves the REPORT path it names and checks the file actually exists on
     disk and is structurally complete (required section headers present,
     every real evidence screenshot in evidences/ is linked from the report,
     the STARTED/COMPLETED timestamps from the signal appear in the body).
  3. If it is not: recovers it. First choice is the exact content the agent
     itself passed to a Write tool call in the same transcript (the model did
     the work but the file never landed) — otherwise a synthesized fallback
     built from the signal's aggregate counts plus whatever evidence
     screenshots exist on disk (real filesystem truth), using the exact
     section structure defined in skills/test-execution:process/SKILL.md
     Step 4 so the file always matches the project's report format.
  4. On the first failure this stop cycle (stop_hook_active is false) it also
     blocks the stop (exit 2) so the model — which usually still has the full
     results in context — gets one chance to overwrite the recovered file
     with the authoritative version. On a repeat failure (stop_hook_active is
     true) it accepts the recovered file and lets the stop proceed, so the
     pipeline never hangs.

This is the single place report-existence is enforced; nothing else in the
pipeline may re-implement this check.
"""

import json
import os
import re
import sys
from datetime import datetime

SIGNAL_RE = re.compile(r"---EXECUTION-COMPLETE---(.*?)---EXECUTION-END---", re.DOTALL)
REQUIRED_HEADERS = ["# Test Execution Report", "## Executive Summary", "## Captured Screenshots"]
EVIDENCE_EXTS = (".png", ".jpg", ".jpeg")

CATEGORY_BY_PREFIX = [
    ("TC-SMK", "SMOKE TESTS"),
    ("TC-HP", "HAPPY PATH"),
    ("TC-FUNC", "FUNCTIONAL TESTS"),
    ("TC-EC", "EDGE CASES"),
    ("TC-EDGE", "EDGE CASES"),
    ("TC-EXP", "EXPLORATORY TESTS"),
    ("TC-DC", "DESIGN COMPARISON"),
]


def log(msg):
    sys.stderr.write(msg + "\n")


def read_hook_input():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def iter_transcript_entries(transcript_path):
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except Exception:
                    continue
    except OSError:
        return


def collect_signal_and_writes(transcript_path):
    """Walk the transcript once; return (last_signal_text_or_None, [(file_path, content), ...])."""
    last_signal = None
    writes = []

    def walk(node):
        nonlocal last_signal
        if isinstance(node, dict):
            if node.get("type") == "text" and isinstance(node.get("text"), str):
                m = list(SIGNAL_RE.finditer(node["text"]))
                if m:
                    last_signal = m[-1].group(1)
            if node.get("name") == "Write" and isinstance(node.get("input"), dict):
                fp = node["input"].get("file_path")
                content = node["input"].get("content")
                if isinstance(fp, str) and isinstance(content, str):
                    writes.append((fp, content))
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    for entry in iter_transcript_entries(transcript_path):
        walk(entry)

    return last_signal, writes


def parse_signal_fields(signal_text):
    fields = {}
    for line in signal_text.strip().splitlines():
        m = re.match(r"^\s*([A-Z_]+):\s*(.*)$", line)
        if m:
            fields[m.group(1)] = m.group(2).strip()
    return fields


def resolve_path(path, cwd):
    if not path:
        return None
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))


def list_evidence_files(report_path):
    evidences_dir = os.path.join(os.path.dirname(report_path), "evidences")
    if not os.path.isdir(evidences_dir):
        return evidences_dir, []
    return evidences_dir, sorted(
        f for f in os.listdir(evidences_dir) if f.lower().endswith(EVIDENCE_EXTS)
    )


def structurally_valid(report_path, fields):
    reasons = []
    if not os.path.isfile(report_path):
        return False, ["file does not exist on disk"]

    try:
        with open(report_path, "r", encoding="utf-8") as f:
            content = f.read()
    except OSError as e:
        return False, [f"file exists but could not be read: {e}"]

    if len(content.strip()) < 100:
        reasons.append("file exists but is empty or too short to be a real report")

    for header in REQUIRED_HEADERS:
        if header not in content:
            reasons.append(f"missing required section '{header}'")

    _, real_shots = list_evidence_files(report_path)
    missing_links = [f for f in real_shots if f not in content]
    if missing_links:
        preview = ", ".join(missing_links[:5])
        more = "..." if len(missing_links) > 5 else ""
        reasons.append(
            f"{len(missing_links)} evidence screenshot(s) exist on disk but are not "
            f"linked from the report: {preview}{more}"
        )

    for label in ("STARTED", "COMPLETED"):
        val = fields.get(label)
        if val and val not in content:
            reasons.append(f"{label} timestamp '{val}' from the completion signal is missing from the report body")

    return (len(reasons) == 0), reasons


def find_recovered_content(writes, report_path):
    target_basename = os.path.basename(report_path)
    for fp, content in reversed(writes):
        if os.path.basename(fp) == target_basename and "# Test Execution Report" in content:
            return content
    for fp, content in reversed(writes):
        if "# Test Execution Report" in content and "test-report" in os.path.basename(fp).lower():
            return content
    return None


def category_for_filename(filename):
    for prefix, category in CATEGORY_BY_PREFIX:
        if filename.startswith(prefix + "-"):
            return category
    return "UNCATEGORIZED"


def tc_id_for_filename(filename):
    m = re.match(r"^(TC-[A-Za-z0-9]+-[A-Za-z0-9]+)-", filename)
    return m.group(1) if m else os.path.splitext(filename)[0]


def build_fallback_report(report_path, fields, evidences_dir, real_shots):
    module = re.sub(r"^test-report-", "", os.path.splitext(os.path.basename(report_path))[0])
    now = fields.get("COMPLETED") or datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    started = fields.get("STARTED", "unknown")
    completed = fields.get("COMPLETED", "unknown")
    execution_level = fields.get("EXECUTION_LEVEL", "unknown")
    total = fields.get("TOTAL", "unknown")
    passed = fields.get("PASSED", "unknown")
    failed = fields.get("FAILED", "unknown")
    blocked = fields.get("BLOCKED", "unknown")
    skipped = fields.get("SKIPPED", "unknown")
    success_rate = fields.get("SUCCESS_RATE", "unknown")
    spec = fields.get("SPEC", "unknown")

    by_tc = {}
    for filename in real_shots:
        tc_id = tc_id_for_filename(filename)
        by_tc.setdefault(tc_id, []).append(filename)

    by_category = {}
    for tc_id, files in by_tc.items():
        category = category_for_filename(files[0])
        by_category.setdefault(category, []).append((tc_id, files))

    lines = []
    lines.append(f"# Test Execution Report — {module}")
    lines.append("")
    lines.append(
        "> ⚠️ **AUTO-RECOVERED REPORT** — the test-execution agent reported completion "
        "but did not persist a valid report file to disk. This file was reconstructed "
        "automatically by the `pipeline-verify-report.sh` hook from the agent's own "
        "completion signal and the evidence screenshots found in `evidences/`. Per-test "
        "pass/fail classification could not be recovered and is marked ❓ UNKNOWN below — "
        "re-run test execution for authoritative, fully detailed results."
    )
    lines.append("")
    lines.append(f"**Spec:** `{spec}`")
    lines.append(f"**Date:** {now}")
    lines.append("**Executed with:** Playwright MCP — server `playwright_headed` (MCP tool, not Node.js code)")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Executive Summary")
    lines.append("")
    lines.append(f"**Execution started:** {started}")
    lines.append(f"**Execution completed:** {completed}")
    lines.append(f"**Execution level:** {execution_level}")
    lines.append("")
    lines.append("| Category          | Total | ✅ Passed | ❌ Failed | ⚠️ Blocked | ⏭ Skipped |")
    lines.append("| ----------------- | ----- | --------- | --------- | ---------- | ---------- |")
    lines.append("| Smoke Tests       | —     | —         | —         | —          | —          |")
    lines.append("| Happy Path        | —     | —         | —         | —          | —          |")
    lines.append("| Functional Tests  | —     | —         | —         | —          | —          |")
    lines.append("| Edge Cases        | —     | —         | —         | —          | —          |")
    lines.append("| Exploratory Tests | —     | —         | —         | —          | —          |")
    lines.append("| Design Comparison | —     | —         | —         | —          | —          |")
    lines.append(f"| **TOTAL**         | **{total}** | **{passed}** | **{failed}** | **{blocked}** | **{skipped}** |")
    lines.append("")
    lines.append(f"**Success rate: {success_rate}** — per-category breakdown unavailable in an auto-recovered report")
    lines.append("")
    lines.append("---")
    lines.append("")

    for category in ["SMOKE TESTS", "HAPPY PATH", "FUNCTIONAL TESTS", "EDGE CASES", "EXPLORATORY TESTS", "DESIGN COMPARISON", "UNCATEGORIZED"]:
        entries = by_category.get(category)
        if not entries:
            if category == "UNCATEGORIZED" or category == "DESIGN COMPARISON":
                continue
            lines.append(f"## {category} (recovered from evidence — none found)")
            lines.append("")
            lines.append("No evidence screenshots were found on disk for this category.")
            lines.append("")
            continue

        lines.append(f"## {category} (recovered from evidence)")
        lines.append("")
        lines.append("| ID | Description | Result | Timestamp | Evidence | Detail |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for tc_id, files in sorted(entries):
            file_links = ", ".join(f"`evidences/{f}`" for f in files)
            lines.append(
                f"| {tc_id} | (unavailable — recovered from evidence only) | ❓ UNKNOWN | "
                f"unavailable | {file_links} | "
                f"Reconstructed from evidence screenshot(s) on disk. Original "
                f"pass/fail result unavailable because the agent did not persist a valid "
                f"report; inspect the screenshot(s) for the actual end state. |"
            )
        lines.append("")

    lines.append("## Captured Screenshots")
    lines.append("")
    lines.append("| File | Description |")
    lines.append("| ------------------------- | ----------------------------------------- |")
    if real_shots:
        for f in real_shots:
            lines.append(f"| `evidences/{f}` | Evidence recovered from disk during report auto-recovery |")
    else:
        lines.append("| (none) | No evidence screenshots were found in `evidences/` |")
    lines.append("")

    return "\n".join(lines)


def main():
    hook_input = read_hook_input()
    transcript_path = hook_input.get("transcript_path")
    stop_hook_active = bool(hook_input.get("stop_hook_active"))
    cwd = os.getcwd()

    if not transcript_path or not os.path.isfile(transcript_path):
        return 0

    signal_text, writes = collect_signal_and_writes(transcript_path)
    if not signal_text:
        return 0  # This stop has nothing to do with test-execution.

    fields = parse_signal_fields(signal_text)
    report_path = resolve_path(fields.get("REPORT"), cwd)
    if not report_path:
        return 0  # Malformed signal — nothing we can verify against.

    valid, reasons = structurally_valid(report_path, fields)
    if valid:
        return 0

    log(f"[pipeline-verify-report] Report validation failed for {report_path}:")
    for r in reasons:
        log(f"  - {r}")

    evidences_dir, real_shots = list_evidence_files(report_path)
    recovered_content = find_recovered_content(writes, report_path)
    source = "transcript Write tool-call capture"
    final_content = recovered_content
    if not final_content:
        source = "synthesized fallback (no usable Write call found in transcript)"
        final_content = build_fallback_report(report_path, fields, evidences_dir, real_shots)

    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(final_content)

    valid2, reasons2 = structurally_valid(report_path, fields)
    if not valid2 and source.startswith("transcript"):
        source = "synthesized fallback (recovered transcript content was also incomplete)"
        final_content = build_fallback_report(report_path, fields, evidences_dir, real_shots)
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(final_content)

    log(f"[pipeline-verify-report] Recovered {report_path} via {source}.")

    if stop_hook_active:
        log("[pipeline-verify-report] Already retried once this stop cycle — accepting the recovered file.")
        return 0

    print(
        f"Report validation failed for {report_path}:\n"
        + "\n".join(f"- {r}" for r in reasons)
        + f"\n\nA report has been written to that exact path automatically (source: {source}), "
        "so a file now exists on disk. If the full per-test results for this run are still in "
        "your context, use the Write tool now to overwrite that same path with the complete, "
        "accurate report — follow skills/test-execution:process/SKILL.md Step 4 exactly. "
        "Then finish normally.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
