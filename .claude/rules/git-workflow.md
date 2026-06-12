---
description: Git and PR workflow conventions for all Pulse Energy repos
priority: high
---
# Git Workflow Rules

## Commits
- Write concise commit messages focused on "why" not "what"
- Never amend published commits
- Never force push to main/master/staging branches
- Never skip pre-commit hooks (`--no-verify`)

## Pull Requests
- PR titles should be under 70 characters
- Include a Summary section with 1-3 bullet points
- Include a Test Plan section with verification steps
- When reviewing PRs, provide feedback in high-to-low priority order
- Use importance emojis (red/orange/yellow dots) for review findings
- Always mention file path, line number, and provide code suggestions

## Branches
- Feature branches from `main` or `develop` depending on repo convention
- Use descriptive branch names: `feature/`, `fix/`, `chore/`, `refactor/`
