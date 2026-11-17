---
title: Audit rules
description: Every rule scripts/audit.sh checks, by ID, with the OpenSSF Baseline control it covers.
type: reference
audience: [user, admin]
---

# Audit rules

`scripts/audit.sh` checks a repository against the standard and prints one
line per rule: `PASS`, `FAIL` or `N/A`, the rule ID, and what was checked.
IDs are stable: a rule keeps its ID while it exists, and a removed rule's ID
is never reused.

The Baseline column names the
[OpenSSF OSPS Baseline](https://baseline.openssf.org/) control (release
v2026.08.28) that the rule provides evidence for. Most controls are Level 1,
the level the Baseline sets for a project with any number of maintainers.
Controls marked L2 belong to Level 2.

## Running it

```bash
scripts/audit.sh OWNER/REPO [LOCAL_DIR|-]   # one repository
scripts/audit.sh --all OWNER [PARENT]       # every owned source repository
scripts/audit.sh --as LOGIN OWNER/REPO DIR  # read GitHub as another login
```

- File, content, hook and workflow rules read a local clone. With `-`, or
  under `--all` when `PARENT/OWNER/NAME` is not a clone, they are skipped.
- `--as` uses another GitHub login's token. Rules that only an admin can
  read report `N/A (needs admin to read)` when that login is not an admin.
- To skip a rule on purpose, add its ID with the reason to
  `.github/repo-standard-exclude` (`RS-DEP-02  # no package`). It then
  reports `N/A (excluded by the repo)`.

The audit exits with status 1 when any rule fails.

## Files

| ID | Rule | Baseline |
|---|---|---|
| RS-FILE-01 | `README.md` | OSPS-DO-01.01 |
| RS-FILE-02 | `CONTRIBUTING.md` | OSPS-GV-03.01 |
| RS-FILE-03 | `SECURITY.md` | OSPS-VM-02.01 |
| RS-FILE-04 | `CODE_OF_CONDUCT.md` | |
| RS-FILE-05 | `SUPPORT.md` | OSPS-GV-02.01 |
| RS-FILE-06 | `AGENTS.md` | |
| RS-FILE-07 | `.editorconfig` | |
| RS-FILE-08 | `.gitignore` | OSPS-BR-07.01 |
| RS-FILE-09 | `.pre-commit-config.yaml` | |
| RS-FILE-10 | `release-please-config.json` | OSPS-BR-04.01 (L2) |
| RS-FILE-11 | `.release-please-manifest.json` | OSPS-BR-02.01 (L2) |
| RS-FILE-12 | `.github/pull_request_template.md` | |
| RS-FILE-13 | `.github/dependabot.yml` | |
| RS-FILE-14 | `.github/CODEOWNERS` | |
| RS-FILE-15 | `.github/ISSUE_TEMPLATE/config.yml` | OSPS-DO-02.01 (file only) |
| RS-FILE-16 | `.github/workflows/ci.yml` | OSPS-QA-06.01 (L2) |
| RS-FILE-17 | `.github/workflows/pr-title.yml` | |
| RS-FILE-18 | `.github/workflows/release-please.yml` | |
| RS-FILE-19 | `.github/workflows/links.yml` | |
| RS-FILE-20 | `.github/workflows/main-guard.yml` | OSPS-AC-03.01 (private repositories) |
| RS-FILE-21 | `.claude/settings.json` | |
| RS-FILE-22 | `.vale.ini` | |
| RS-FILE-23 | `.lychee.toml` | |
| RS-FILE-24 | `scripts/check_docs.py` | |
| RS-FILE-25 | `docs/index.md` | OSPS-DO-01.01 |
| RS-FILE-26 | `docs/dev/index.md` | |
| RS-LIC-01 | `LICENSE`, unless the README states "No license: all rights reserved" | OSPS-LE-03.01 |

## Content

| ID | Rule | Baseline |
|---|---|---|
| RS-DOC-01 | `README.md` starts with a title and has at least 10 lines | OSPS-DO-01.01 |
| RS-DOC-02 | `SECURITY.md` names a private reporting route | OSPS-VM-02.01, OSPS-VM-03.01 (L2) |
| RS-DOC-03 | `CONTRIBUTING.md` describes the pull request process | OSPS-GV-03.01 |
| RS-DOC-04 | `.scratch/` is gitignored | |
| RS-DOC-05 | No committed plan or notes files | |

## Hooks

| ID | Rule | Baseline |
|---|---|---|
| RS-HOOK-01 | pre-commit hook revisions frozen to commit SHAs | |
| RS-HOOK-02 | Hook configured: `vale` | |
| RS-HOOK-03 | Hook configured: `lychee` | |
| RS-HOOK-04 | Hook configured: `check-docs` | |
| RS-HOOK-05 | Hook configured: `no-scratch-files` | |
| RS-HOOK-06 | Hook configured: `no-ai-attribution` | |
| RS-HOOK-07 | Vale Google style vendored in `.vale/` | |
| RS-HOOK-08 | `commit-msg` hook installed in the local clone | |
| RS-HOOK-09 | Pre-push guard installed in the local clone | OSPS-AC-03.01 (private repositories) |

## Workflows

| ID | Rule | Baseline |
|---|---|---|
| RS-CI-01 | `ci.yml` has the aggregate `ci` job and a `secrets` job | OSPS-BR-07.01 |
| RS-CI-02 | Every action pinned to a full commit SHA | |
| RS-CI-03 | Every workflow sets top-level `permissions` | OSPS-AC-04.01 (L2) |
| RS-CI-04 | No `pull_request_target` trigger | OSPS-BR-01.03 |
| RS-CI-05 | Untrusted event text (titles, bodies, branch names) reaches scripts only through `env` | OSPS-BR-01.01 |

RS-CI-05 is a text match. It flags an expression such as
`${{ github.event.pull_request.title }}` or `${{ github.head_ref }}`
anywhere except as the value of an `env` entry.

## Dependencies and releases

| ID | Rule | Baseline |
|---|---|---|
| RS-DEP-01 | Dependabot covers `github-actions` and `pre-commit` | |
| RS-DEP-02 | A dependency manifest exists (`pyproject.toml`, `package.json`, `go.mod`, `DESCRIPTION` or `Package.swift`); N/A for the docs overlay | OSPS-QA-02.01 |
| RS-DEP-03 | No committed binaries or build output | OSPS-QA-05.01, OSPS-QA-05.02 |
| RS-REL-01 | release-please tags are plain `vX.Y.Z` | OSPS-BR-02.01 (L2) |
| RS-REL-02 | `.github/repo-standard.yml` records the standard version | |
| RS-REL-03 | That version is the current release of the standard | |
| RS-REL-04 | The `RELEASE_APP_CLIENT_ID` variable is set | |

## Settings

| ID | Rule | Baseline |
|---|---|---|
| RS-LIC-02 | GitHub recognizes the license | OSPS-LE-02.01 |
| RS-SET-01 | Squash merge only | |
| RS-SET-02 | Squash commit title is the pull request title | |
| RS-SET-03 | Squash commit message is the pull request body | |
| RS-SET-04 | Branches are deleted on merge | |
| RS-SET-05 | The default branch is `main` | |
| RS-SET-06 | Ruleset `main` is active (public repositories) | OSPS-AC-03.01 |
| RS-SET-07 | Ruleset `main` requires the `ci` and `pr-title` checks | OSPS-QA-03.01 (L2) |
| RS-SET-08 | Ruleset `main` blocks deletion and requires a pull request | OSPS-AC-03.01, OSPS-AC-03.02 |
| RS-SET-09 | Ruleset `main` has no bypass actors (admin) | OSPS-AC-03.01 |
| RS-SET-10 | Secret scanning push protection (public repositories, admin) | OSPS-BR-07.01 |
| RS-SET-11 | Public overlay: `codeql.yml` | |
| RS-SET-12 | Public overlay: `scorecard.yml` | |
| RS-SET-13 | Dependabot alerts are on (admin) | |

On private repositories on the Free plan, RS-SET-06 to RS-SET-12 are N/A:
GitHub offers neither rulesets nor push protection there. RS-HOOK-09 and
RS-FILE-20 stand in for the ruleset.

## Level 1 controls the audit cannot check

| Baseline | Why | How the standard meets it |
|---|---|---|
| OSPS-AC-01.01 | Account setting, not visible per repository | Turn on two-factor authentication (passkeys count) for every account |
| OSPS-AC-02.01 | Personal accounts have no default collaborator role | Add collaborators with the lowest role they need |
| OSPS-BR-03.01, OSPS-BR-03.02 | Always true on GitHub | GitHub serves repositories and releases over HTTPS only |
| OSPS-DO-02.01 | The issue templates are checked, not their wording | `bug_report.yml` in the template |
| OSPS-LE-02.02, OSPS-LE-03.02 | Release assets are built per language | Package builds include the license file |
| OSPS-QA-01.01, OSPS-QA-01.02 | True for every public GitHub repository | Not met by private repositories, by design |
| OSPS-QA-04.01 | Single-repository projects | List related repositories in the README when there are any |
