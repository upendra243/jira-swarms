# Changelog

## 1.2.0 (unreleased)

- **Workflow enhancements** (from jira-workflow learnings):
  - Step 2d: Explicit browser-testing applicability question (default YES) in Technical layer.
  - Step 5c-post: Mandatory Jira comments for Release Notes (even when no migration).
  - Step 5d: Validate test record IDs before browser testing; ticket categories (UI mandatory vs backend optional); artifacts directory setup; test summary; failure handling (downgrade SUCCESS→PARTIAL when all tests fail); Jira screenshot rules table; mandatory Jira note when browser testing skipped.
  - Step 6b: Release Notes comment flow; comment rules and template.
  - Step 6c: Discover valid Jira transitions before moving.
  - Worker prompt: ASCII-only rule for legacy codebases (Python 2).
  - Step 4f: Docker troubleshooting (AttributeError, OperationalError, missing dirs, Redis).
  - Epic workflow: Benefits section.
  - Error handling: Orchestrator vs Worker vs Browser circuit breakers clarified.
- Add `JIRA_MAIN_BRANCH` (default `master`) for repos using `main`.
- Add `WORKFLOW_DIAGRAM.md` (Mermaid flowchart).
- Make configuration **per-project** by treating `~/.jira-swarms/config/<project-id>.env` as the primary source of Jira and PR provider settings.
- Add a **first-run setup wizard** (per repo) in the orchestration flow to collect Jira, provider, and worktree copy-path settings and write them into the per-project config file.
- Introduce `JIRA_WORKTREE_COPY_PATHS` (comma-separated paths) for copying multiple local config files into each worktree, with backward-compatible support for legacy `JIRA_LOCAL_CONFIG_PATH`.
- Update docs and diagnostics to prefer per-project config over global environment variables, while still allowing env vars as explicit overrides (e.g. for CI).
- Make the one-click installer more robust:
  - Detect macOS vs Ubuntu/Debian vs other Linux and provide OS-specific guidance for missing Git and Jira CLI.
  - On macOS with Homebrew, optionally install `git` and `go-jira` interactively (no sudo).
  - On Ubuntu/Debian and other platforms, fail fast with clear, copy-pasteable commands for installing Git and a Jira CLI.

## 1.1.0

- Add generic `create-pr.sh` wrapper and `create-gh-pr.sh` to support both Bitbucket and GitHub PRs.
- Update docs and diagnostics for provider-agnostic PR configuration (`PR_PROVIDER`, Bitbucket/GitHub env vars).

## 1.0.0 (initial)

- Initial public release: genericized multi-Jira workflow for Cursor.
- Env-driven scripts (create-worktree, cleanup, build-image, upload-jira-screenshots, batch-notify-telegram).
- Bundled fetch-jira-ticket.sh, create-bb-pr.sh (Bitbucket), browser-login-example.py
- SKILL.md and reference.md for jira-swarms; README, LICENSE (MIT), CONTRIBUTING, SECURITY
