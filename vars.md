BASE_URL = https://your-app-domain.com
AUTH_EMAIL = your-login-email@example.com
AUTH_PASSWORD = your-login-password

Note: AUTH_EMAIL / AUTH_PASSWORD above start as placeholders. The first time any flow in this
suite needs an account and these are still the placeholder values shown above — test-execution
running a test case that creates an account, or spec-wizard-generate analyzing a page whose
AUTH_MODE is "new" — it generates a persistent Yopmail-based test identity, verifies it, and
overwrites these two lines with the real values so every later run (by either flow) reuses the
same account instead of signing up again. To force a fresh account on the next run, restore the
placeholder values. This procedure is defined once in ${CLAUDE_PLUGIN_ROOT}/skills/shared:account-identity/SKILL.md
(inside the plugin's own bundle — this file is never copied into the project).
