#!/bin/bash
# PIPELINE HOOK — ENFORCE TEST-EXECUTION REPORT PERSISTENCE
#
# Fires on SubagentStop for the test-execution agent, and defensively on
# every Stop (for the "invoked directly, no coordinator" case). Nothing
# upstream of this hook ever confirmed that test-execution's Write call for
# test-report-{module}.md actually succeeded — the skill only ever *instructs*
# the model to write it and then emit a ---EXECUTION-COMPLETE--- signal.
# A model can emit that signal, and a human-readable "report generated"
# summary, without the Write tool call ever having happened or landed on
# disk. This hook reads the same transcript the agent just produced, checks
# the REPORT path from its own completion signal is really there and
# structurally complete, and recovers/synthesizes it before letting the
# stop proceed if it isn't — so the file's existence is enforced
# mechanically instead of trusted from the model's self-report.
#
# All parsing/validation/recovery logic lives in verify_execution_report.py.
# This script only pipes stdin through, exactly like every other hook here.

python3 "${CLAUDE_PLUGIN_ROOT}/hooks/verify_execution_report.py"
exit $?
