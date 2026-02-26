# Contributing to jira-swarms

Thanks for your interest in contributing.

## How to contribute

- **Bug reports and feature ideas:** Open a [GitHub Issue](https://github.com/upendra243/jira-swarms/issues). Describe the problem or idea and, if relevant, your environment (Cursor version, OS, shell).
- **Code and docs:** Open a Pull Request. Branch from `main` (or `master`), make your changes, and ensure scripts stay bash/shell compatible and docs stay clear.

## What to avoid

- Do not commit secrets, API tokens, or credentials. Use env vars and document them in README or `.env.example`.
- Do not add project-specific paths or company names to the skill or scripts; keep the repo generic and configurable via environment variables.

## Code style

- Shell scripts: `set -euo pipefail`; quote variables; use `bash` where needed for portability.
- Prefer small, focused changes and clear commit messages.
