# Git Commit Checklist

Use this checklist to ensure every commit in the project follows our standards. Tick off each item before pushing or opening a pull request.

1. Branch & PR Naming
   - [ ] Branch name follows `<type>/<JIRA-ISSUE>-short-description`  
     • type ∈ {feature, fix, chore, docs, refactor, test}  
     • Example: `feature/PROJ-123-add-user-login`  
   - [ ] Pull request title matches the branch name or issue title

2. Commit Granularity & Scope
   - [ ] Commits are _atomic_: one logical change per commit  
   - [ ] No mixing of unrelated changes (formatting + feature code together)

3. Commit Message Format
   - [ ] Header line ≤ 50 characters  
   - [ ] Header uses imperative mood: “Add validation”, not “Added” or “Adds”  
   - [ ] Header follows `<type>(<scope>): <short summary>`  
     • type ∈ {feat, fix, chore, docs, style, refactor, test, perf}  
     • scope is optional but recommended (e.g., “auth”, “ui”, “api”)  
     • Example: `feat(auth): add JWT refresh endpoint`  
   - [ ] Blank line between header and body
   - [ ] Body lines wrap at ≤ 72 characters  
   - [ ] Body includes:  
     • What changed and why (context)  
     • Any side effects or migration steps  
   - [ ] Footer (if needed) for:  
     • Issue references: `Closes PROJ-123`  
     • Breaking changes: `BREAKING CHANGE: <description>`

4. Code Quality & Testing
   - [ ] All tests pass locally (`npm test`, `go test`, etc.)  
   - [ ] Linting and formatting checks complete without errors (`npm run lint`, `gofmt`, etc.)  
   - [ ] New code covered by unit/integration tests where applicable

5. Pre-Commit Hooks & Signing
   - [ ] Pre-commit hooks (lint-staged, pre-commit) ran and passed  
   - [ ] Commits are GPG-signed if required by policy

6. Rebasing & History
   - [ ] Branch is up-to-date with `main` (rebase rather than merge when possible)  
   - [ ] No “WIP” or merge commits in final history—use interactive rebase to squash/fixup

7. PR Review Readiness
   - [ ] Commit history is clean and descriptive  
   - [ ] PR description includes:  
     • Summary of changes  
     • Link to JIRA/story/task  
     • Screenshots or logs (if UI or critical flows)  
   - [ ] All checklist items here are completed

By following this checklist, we keep our Git history clear, enforce best practices, and make reviews smoother for everyone.
