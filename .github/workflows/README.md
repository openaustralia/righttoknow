# GitHub Actions Workflows

This repository includes automated workflows for pull request management and code quality.

## Workflows

### 1. Lint Code Base (`lint.yml`)

Automatically runs code linting on all pull requests using [Super Linter](https://github.com/super-linter/super-linter).

**Triggers:**
- Push to `staging` or `production` branches
- Pull requests targeting `staging` or `production` branches

**Languages checked:**
- Ruby
- JavaScript
- CSS/SCSS

### 2. PR Review Automation (`pr-automation.yml`)

Implements automated pull request review management.

**Features:**
- **Team Review Assignment**: Automatically requests review from `openaustralia/team-right-to-know` team on new PRs (excludes draft PRs)
- **Auto-approval**: Non-draft PRs that haven't been reviewed after 48 hours are automatically approved (only if status checks pass)

**Triggers:**
- PR events: opened, synchronize, reopened
- Scheduled: runs hourly to check for PRs eligible for auto-approval

## Required Setup

To fully implement the PR automation requirements, the following repository settings should be configured:

### Branch Protection Rules

Configure branch protection for the `production` branch with:

1. **Require pull request reviews before merging**
   - Required number of reviewers: 1
   - Dismiss stale reviews when new commits are pushed
   - Require review from code owners (if CODEOWNERS file exists)

2. **Require status checks to pass before merging**
   - Require branches to be up to date before merging
   - Required status checks: `Lint Code Base`

3. **Require teams to review**
   - Add `openaustralia/team-right-to-know` as required reviewers

### Team Configuration

Ensure the `openaustralia/team-right-to-know` team exists and has appropriate permissions to review PRs in this repository.

## Security Considerations

- The auto-approval workflow only approves PRs where all status checks have passed
- PRs with failed status checks are skipped from auto-approval
- Draft PRs are excluded from both team review assignment and auto-approval
- Team members can still request changes or re-review auto-approved PRs
- All auto-approvals are logged and include explanatory comments