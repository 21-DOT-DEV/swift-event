# AGENTS.md (.github)

This directory contains GitHub configuration and CI workflows.

## Boundaries (strict)

- Do not broaden GitHub Actions `permissions` without a clear justification.
- Do not print or log secrets/tokens.
- Do not add new third-party actions without asking.

## Workflow conventions

- **Least-privilege pattern for private repos**: set `permissions: {}` at the **workflow** level (deny-by-default baseline for any job that omits its own block) and grant the **minimum** each job needs at the job level. For `actions/checkout` against a private repo, that minimum is `contents: read`. A bare `permissions: {}` at the job level strips `contents: read` and causes `actions/checkout` to fail with a 404 "repository not found" error on private repos.
- Workflows use `env:` blocks for context values — no inline `${{ }}` interpolation in `run:` scripts.
- Avoid fragile shell output capture for UTF-8 / multiline content; prefer temp files and tools like `jq` reading from files.
- Subtree-automation workflows (`check-subtree-updates.yml`, `update-subtree.yml`) require a `BOT_TOKEN` secret with `repo` + `workflow` + `pull_request:write` scopes. The default `GITHUB_TOKEN` cannot dispatch other workflows.

## Validation

- After changing workflows, run `swift test` and `docker build .` locally, and push to trigger a real CI run (the private-repo `permissions` failure mode only appears on the GitHub runner, not locally).
