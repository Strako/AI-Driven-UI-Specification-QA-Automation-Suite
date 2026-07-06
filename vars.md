BASE_URL = https://your-app-domain.com
AUTH_EMAIL = your-login-email@example.com
AUTH_PASSWORD = your-login-password

Note: AUTH_EMAIL / AUTH_PASSWORD above start as placeholders. The first time test-execution
runs a test case that creates an account and these are still the placeholder values shown
above, it generates a persistent Yopmail-based test identity, verifies it, and overwrites
these two lines with the real values so every later run reuses the same account instead of
signing up again. To force a fresh account on the next run, restore the placeholder values.
